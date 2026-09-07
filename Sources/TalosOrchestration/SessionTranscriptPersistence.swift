import Foundation
import TalosCore
import TalosPersistence
import TalosProjectLibrary

/// Where a session's transcript and its own resume token live on disk — one
/// row per ``SessionTranscriptEntry``, cascading on delete like
/// `session_token_records` does, plus the `session_records` column a resume
/// reads to relaunch the agent. "Sessions are resumable, and output is
/// copyable and exportable" · "Resume across app restart works, since
/// records are in SQLite."
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
public enum SessionTranscriptSchema {
    /// Runs after ``GatedDecisionLogSchema``'s, since both migrate the one
    /// shared database rather than one of their own.
    public static let migration = Migration(
        version: GatedDecisionLogSchema.migration.version + 1,
        name: "add resume token and session transcript entries",
        sql: """
        ALTER TABLE session_records ADD COLUMN resume_token TEXT;
        CREATE TABLE session_transcript_entries (
            id INTEGER PRIMARY KEY,
            project_id TEXT NOT NULL,
            session_id TEXT NOT NULL REFERENCES session_records(id) ON DELETE CASCADE,
            seq INTEGER NOT NULL,
            kind TEXT NOT NULL,
            text TEXT,
            call_id TEXT,
            tool_name TEXT,
            tool_targets TEXT
        );
        """
    )
}

/// The transcript and resume-token side of ``SQLiteSessionRecordStore`` —
/// split into its own file because the base store, with both tables' worth of
/// read/write logic in one place, ran past this module's own file-length
/// limit.
extension SQLiteSessionRecordStore {
    /// One row per ``SessionTranscriptEntry``, in arrival order. `text`,
    /// `tool_name`, and `tool_targets` are redacted before they reach disk —
    /// this is content Talos did not author, the same rule every other call
    /// site logging agent output already follows.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
    func insertTranscript(
        _ transcript: [SessionTranscriptEntry],
        project: ProjectIdentifier,
        sessionID: UUID
    ) async throws {
        for (seq, entry) in transcript.enumerated() {
            let bindings: [DatabaseValue] = switch entry {
            case let .output(text):
                [
                    .text(project.rawValue),
                    .text(sessionID.uuidString),
                    .int(Int64(seq)),
                    .text("output"),
                    .text(LogRedaction.redacted(text)),
                    .null,
                    .null,
                    .null
                ]
            case let .toolCall(id, name, targets):
                [
                    .text(project.rawValue),
                    .text(sessionID.uuidString),
                    .int(Int64(seq)),
                    .text("toolCall"),
                    .null,
                    .text(id),
                    .text(LogRedaction.redacted(name)),
                    .text(Self.encodedTargets(targets.map(LogRedaction.redacted)))
                ]
            }
            try await database.run(
                """
                INSERT INTO session_transcript_entries (
                    project_id, session_id, seq, kind, text, call_id, tool_name, tool_targets
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """,
                bindings: bindings
            )
        }
    }

    /// The transcript ``records(project:from:to:)``'s own row does not carry —
    /// "a prior session can be resumed with its transcript... intact", in
    /// arrival order.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
    public func transcriptEntries(
        project: ProjectIdentifier,
        sessionID: UUID
    ) async throws -> [SessionTranscriptEntry] {
        let rows = try await database.query(
            """
            SELECT kind, text, call_id, tool_name, tool_targets
            FROM session_transcript_entries
            WHERE project_id = ? AND session_id = ?
            ORDER BY seq ASC;
            """,
            bindings: [.text(project.rawValue), .text(sessionID.uuidString)]
        )
        return try rows.map(Self.transcriptEntry(from:))
    }

    /// The `transcriptEntries(project:sessionID:)` `SELECT` list, in order.
    private enum TranscriptColumn: Int, CaseIterable {
        case kind, text, callID, toolName, toolTargets
    }

    private static func transcriptEntry(from row: [DatabaseValue]) throws -> SessionTranscriptEntry {
        guard
            row.count == TranscriptColumn.allCases.count,
            case let .text(kind) = row[TranscriptColumn.kind.rawValue]
        else {
            throw SessionRecordsStoreError.malformedRow
        }
        switch kind {
        case "output":
            guard case let .text(text) = row[TranscriptColumn.text.rawValue] else {
                throw SessionRecordsStoreError.malformedRow
            }
            return .output(text)
        case "toolCall":
            guard
                case let .text(callID) = row[TranscriptColumn.callID.rawValue],
                case let .text(toolName) = row[TranscriptColumn.toolName.rawValue],
                case let .text(toolTargets) = row[TranscriptColumn.toolTargets.rawValue]
            else {
                throw SessionRecordsStoreError.malformedRow
            }
            return .toolCall(id: callID, name: toolName, targets: Self.decodedTargets(toolTargets))
        default:
            throw SessionRecordsStoreError.malformedRow
        }
    }

    /// `[String]` as JSON — the one shape simple enough that a hand-rolled
    /// delimiter would be a second, unnecessary encoding to keep in sync with
    /// this one.
    private static func encodedTargets(_ targets: [String]) -> String {
        guard let data = try? JSONEncoder().encode(targets), let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    private static func decodedTargets(_ text: String) -> [String] {
        guard
            let data = text.data(using: .utf8),
            let targets = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return targets
    }
}
