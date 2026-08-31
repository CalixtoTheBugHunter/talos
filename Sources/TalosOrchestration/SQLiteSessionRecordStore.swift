import Foundation
import TalosAdapters
import TalosPersistence
import TalosProjectLibrary

/// Where session records live on disk: two tables, `session_records` and
/// `session_token_records`, the latter cascading on delete — the exact shape
/// already proven generically by `MigrationRunnerTests`, applied to the real
/// schema. "Deletion is real deletion, including the associated token
/// records. Nothing is soft-deleted and kept around."
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#chat-history-management
public enum SessionRecordsSchema {
    /// The first migration any Talos database applies — nothing else has
    /// defined one yet.
    public static let migration = Migration(
        version: 1,
        name: "create session records",
        sql: """
        CREATE TABLE session_records (
            id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            sub_function TEXT NOT NULL,
            agent_name TEXT NOT NULL,
            outcome TEXT NOT NULL,
            failure_reason TEXT,
            started_at REAL NOT NULL,
            duration REAL NOT NULL,
            tool_call_count INTEGER NOT NULL,
            approval_count INTEGER NOT NULL,
            denial_count INTEGER NOT NULL,
            retry_count INTEGER NOT NULL,
            token_overhead_ratio REAL NOT NULL
        );
        CREATE TABLE session_token_records (
            id INTEGER PRIMARY KEY,
            project_id TEXT NOT NULL,
            session_id TEXT NOT NULL REFERENCES session_records(id) ON DELETE CASCADE,
            input_tokens INTEGER,
            output_tokens INTEGER,
            model TEXT,
            unavailable_reason TEXT,
            agent_version TEXT
        );
        """
    )
}

/// Persists ``SessionRecord`` to the local SQLite database, and answers the
/// two questions the Monitor Screen and Chat History Management need:
/// "queryable by project and by time range", and real deletion.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model
public actor SQLiteSessionRecordStore: SessionRecordWriter {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    /// Stage 9. Non-throwing per the protocol: a write failure is logged to
    /// standard error rather than surfaced, so a persistence fault can never
    /// rewrite the session's outcome. Retry and durability belong here, per
    /// the protocol's own contract — this implementation's answer is "log and
    /// move on" rather than an unbounded retry loop.
    public func write(_ record: SessionRecord) async {
        do {
            try await insert(record)
        } catch {
            let message = "SQLiteSessionRecordStore: failed to write session record \(record.id): \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    }

    private func insert(_ record: SessionRecord) async throws {
        try await database.run(
            """
            INSERT INTO session_records (
                id, project_id, sub_function, agent_name, outcome, failure_reason,
                started_at, duration, tool_call_count, approval_count, denial_count,
                retry_count, token_overhead_ratio
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(record.id.uuidString),
                .text(record.project.rawValue),
                .text(record.subFunction.rawValue),
                .text(record.agentName),
                .text(record.outcome.classification.rawValue),
                record.outcome.failureReason.map(DatabaseValue.text) ?? .null,
                .double(record.startedAt.timeIntervalSince1970),
                .double(record.duration),
                .int(Int64(record.toolCallCount)),
                .int(Int64(record.approvalCount)),
                .int(Int64(record.denialCount)),
                .int(Int64(record.retryCount)),
                .double(record.tokenOverheadRatio)
            ]
        )

        guard let tokenReport = record.outcome.tokenReport else { return }
        try await insertTokenReport(tokenReport, project: record.project, sessionID: record.id)
    }

    private func insertTokenReport(
        _ tokenReport: TokenReport,
        project: ProjectIdentifier,
        sessionID: UUID
    ) async throws {
        let bindings: [DatabaseValue] = switch tokenReport {
        case let .measured(counts, model):
            [
                .text(project.rawValue),
                .text(sessionID.uuidString),
                .int(Int64(counts.input)),
                .int(Int64(counts.output)),
                .text(model),
                .null,
                .null
            ]
        case let .unavailable(unavailable):
            [
                .text(project.rawValue),
                .text(sessionID.uuidString),
                .null,
                .null,
                .null,
                .text(unavailable.reason.storageValue),
                unavailable.agentVersion.map(DatabaseValue.text) ?? .null
            ]
        }
        try await database.run(
            """
            INSERT INTO session_token_records (
                project_id, session_id, input_tokens, output_tokens, model,
                unavailable_reason, agent_version
            ) VALUES (?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: bindings
        )
    }

    /// "Records are queryable by project and by time range for the Monitor
    /// Screen" — ordered oldest first, the order a time-range chart reads.
    public func records(
        project: ProjectIdentifier,
        from start: Date,
        to end: Date
    ) async throws -> [StoredSessionRecord] {
        let rows = try await database.query(
            """
            SELECT id, sub_function, agent_name, outcome, started_at, duration,
                   tool_call_count, approval_count, denial_count, retry_count,
                   token_overhead_ratio
            FROM session_records
            WHERE project_id = ? AND started_at >= ? AND started_at <= ?
            ORDER BY started_at ASC;
            """,
            bindings: [
                .text(project.rawValue),
                .double(start.timeIntervalSince1970),
                .double(end.timeIntervalSince1970)
            ]
        )
        return try rows.map { try Self.storedRecord(from: $0, project: project) }
    }

    /// "Deleting a session really deletes it and its token records." The
    /// dependent `session_token_records` rows are removed by the schema's own
    /// `ON DELETE CASCADE`, never by a second statement this store could skip.
    public func delete(_ id: SessionRecord.ID) async throws {
        try await database.run(
            "DELETE FROM session_records WHERE id = ?;",
            bindings: [.text(id.uuidString)]
        )
    }

    /// The `records(project:from:to:)` `SELECT` list, in order — named so a
    /// row's positional `DatabaseValue`s are indexed by name rather than by
    /// a bare number nobody can trace back to a column.
    private enum RecordColumn: Int, CaseIterable {
        case id, subFunction, agentName, outcome, startedAt, duration
        case toolCallCount, approvalCount, denialCount, retryCount, tokenOverheadRatio
    }

    private static func storedRecord(
        from row: [DatabaseValue],
        project: ProjectIdentifier
    ) throws -> StoredSessionRecord {
        guard
            row.count == RecordColumn.allCases.count,
            case let .text(idText) = row[RecordColumn.id.rawValue],
            let id = UUID(uuidString: idText),
            case let .text(subFunctionRaw) = row[RecordColumn.subFunction.rawValue],
            let subFunction = SubFunction(rawValue: subFunctionRaw),
            case let .text(agentName) = row[RecordColumn.agentName.rawValue],
            case let .text(outcomeRaw) = row[RecordColumn.outcome.rawValue],
            let outcome = SessionOutcomeClassification(rawValue: outcomeRaw),
            case let .double(startedAtEpoch) = row[RecordColumn.startedAt.rawValue],
            case let .double(duration) = row[RecordColumn.duration.rawValue],
            case let .int(toolCallCount) = row[RecordColumn.toolCallCount.rawValue],
            case let .int(approvalCount) = row[RecordColumn.approvalCount.rawValue],
            case let .int(denialCount) = row[RecordColumn.denialCount.rawValue],
            case let .int(retryCount) = row[RecordColumn.retryCount.rawValue],
            case let .double(tokenOverheadRatio) = row[RecordColumn.tokenOverheadRatio.rawValue]
        else {
            throw SessionRecordsStoreError.malformedRow
        }
        return StoredSessionRecord(
            id: id,
            project: project,
            subFunction: subFunction,
            agentName: agentName,
            outcome: outcome,
            startedAt: Date(timeIntervalSince1970: startedAtEpoch),
            duration: duration,
            toolCallCount: Int(toolCallCount),
            approvalCount: Int(approvalCount),
            denialCount: Int(denialCount),
            retryCount: Int(retryCount),
            tokenOverheadRatio: tokenOverheadRatio
        )
    }
}

/// A row this store wrote itself failed to decode back — a schema/code
/// mismatch, never an expected runtime condition.
public enum SessionRecordsStoreError: Error, Equatable, Sendable {
    case malformedRow
}

private extension SessionOutcome {
    /// The free-text reason to persist, when this case carries one. `nil` for
    /// `.contextAssemblyFailed` (named by its ceiling and pinned costs, not a
    /// single string), `.succeeded`, `.stopped`, and `.denied`.
    var failureReason: String? {
        switch self {
        case .contextAssemblyFailed, .succeeded, .stopped, .denied:
            nil
        case let .safeguardsPreCheckDenied(reason):
            reason
        case let .failed(reason, _, _):
            reason
        }
    }

    /// The token usage to persist as this session's `session_token_records`
    /// row, when an agent ever launched. `nil` for `.contextAssemblyFailed`
    /// and `.safeguardsPreCheckDenied` — neither ever reaches an adapter, so
    /// neither has usage to report.
    var tokenReport: TokenReport? {
        switch self {
        case .contextAssemblyFailed, .safeguardsPreCheckDenied:
            nil
        case let .succeeded(tokens), let .stopped(tokens), let .denied(tokens):
            tokens
        case let .failed(_, _, tokens):
            tokens
        }
    }
}

private extension TokenUsageUnavailableReason {
    var storageValue: String {
        switch self {
        case .notReported: "notReported"
        case .unrecognizedFormat: "unrecognizedFormat"
        }
    }
}
