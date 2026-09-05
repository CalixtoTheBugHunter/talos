import Foundation
import TalosAdapters
import TalosCore
import TalosPersistence
import TalosProjectLibrary
import TalosSafeguards

/// Where gated decisions live on disk, in the one shared `talos.sqlite`.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
public enum GatedDecisionLogSchema {
    /// The migration that creates `gated_decision_log` — one after
    /// ``SessionRecordsSchema``'s, since both migrate the one shared database
    /// rather than one of their own.
    public static let migration = Migration(
        version: SessionRecordsSchema.migration.version + 1,
        name: "create gated decision log",
        sql: """
        CREATE TABLE gated_decision_log (
            id INTEGER PRIMARY KEY,
            project_id TEXT NOT NULL,
            session_id TEXT NOT NULL,
            sub_function TEXT NOT NULL,
            request_id TEXT NOT NULL,
            request_prompt TEXT NOT NULL,
            action TEXT NOT NULL,
            classification_kind TEXT NOT NULL,
            classification_tier TEXT,
            actor TEXT NOT NULL,
            outcome TEXT NOT NULL,
            timestamp REAL NOT NULL
        );
        """
    )
}

/// A row read back from ``SQLiteGatedDecisionLog``, for the UI to read the log
/// with — "the log is inspectable by the user".
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
public struct StoredGatedDecisionEntry: Identifiable, Equatable, Sendable {
    public let id: Int
    public let project: ProjectIdentifier
    public let sessionID: UUID
    public let timestamp: Date
    public let subFunction: SubFunction
    public let requestID: String
    /// The CLI's own wording, redacted when ``action`` is one of the three
    /// secret action types — see ``SQLiteGatedDecisionLog/redactedPrompt``.
    public let requestPrompt: String
    public let action: SafeguardsActionType
    public let classification: SafeguardsClassification
    public let actor: SafeguardsDecisionActor
    public let outcome: AgentPermissionDecision

    public init(
        id: Int,
        project: ProjectIdentifier,
        sessionID: UUID,
        timestamp: Date,
        subFunction: SubFunction,
        requestID: String,
        requestPrompt: String,
        action: SafeguardsActionType,
        classification: SafeguardsClassification,
        actor: SafeguardsDecisionActor,
        outcome: AgentPermissionDecision
    ) {
        self.id = id
        self.project = project
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.subFunction = subFunction
        self.requestID = requestID
        self.requestPrompt = requestPrompt
        self.action = action
        self.classification = classification
        self.actor = actor
        self.outcome = outcome
    }
}

/// Persists ``GatedDecisionEntry`` to the local SQLite database.
///
/// An `actor` exposing only `record` and `entries` — no update, no delete.
/// Nothing here can rewrite or remove a row once written: "the log is
/// append-only — no code path updates or deletes an entry."
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
public actor SQLiteGatedDecisionLog: GatedDecisionLog {
    /// Stands in for a secret value that must never reach disk. The action
    /// name itself — `secret.read`, `secret.write`, or `secret.send` — still
    /// records that access happened; only the CLI's own wording, which could
    /// carry the value being read, written, or sent, is replaced.
    private static let redactedPrompt = "[redacted: secret value withheld from the log]"

    private static let secretActionTypes: Set<SafeguardsActionType> = [.secretRead, .secretWrite, .secretSend]

    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    /// Non-throwing per the protocol, and for the reason the session record
    /// writer's own `write` is: a write that could fail and be swallowed
    /// leaves a decision unlogged, and a write that could throw would let a
    /// persistence fault block the gate decision path this entry is already
    /// carried back from. A failure is logged to standard error rather than
    /// surfaced or retried.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
    public func record(_ entry: GatedDecisionEntry) async {
        do {
            try await insert(entry)
        } catch {
            let message = "SQLiteGatedDecisionLog: failed to record decision for request "
                + "\(entry.requestID): \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    }

    private func insert(_ entry: GatedDecisionEntry) async throws {
        let (kind, tier) = Self.classificationColumns(entry.classification)
        try await database.run(
            """
            INSERT INTO gated_decision_log (
                project_id, session_id, sub_function, request_id, request_prompt,
                action, classification_kind, classification_tier, actor, outcome, timestamp
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(entry.project.rawValue),
                .text(entry.sessionID.uuidString),
                .text(entry.subFunction.rawValue),
                .text(entry.requestID),
                .text(Self.redactedPrompt(for: entry)),
                .text(entry.action.rawValue),
                .text(kind),
                tier.map(DatabaseValue.text) ?? .null,
                .text(entry.actor.rawValue),
                .text(entry.outcome.rawValue),
                .double(entry.timestamp.timeIntervalSince1970)
            ]
        )
    }

    /// The CLI's own wording never reaches disk for a secret action type —
    /// "secret values never appear in the log, though secret **access**
    /// does" — while ``GatedDecisionEntry/action`` still names exactly which
    /// of `secret.read` / `secret.write` / `secret.send` was attempted.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
    private static func redactedPrompt(for entry: GatedDecisionEntry) -> String {
        secretActionTypes.contains(entry.action) ? redactedPrompt : entry.requestPrompt
    }

    private static func classificationColumns(_ classification: SafeguardsClassification) -> (String, String?) {
        switch classification {
        case .refused:
            ("refused", nil)
        case let .tier(tier):
            ("tier", tier.rawValue)
        }
    }

    /// Every entry for `project`, oldest first — the order a user reading the
    /// log reads it in.
    public func entries(
        project: ProjectIdentifier,
        from start: Date,
        to end: Date
    ) async throws -> [StoredGatedDecisionEntry] {
        let rows = try await database.query(
            """
            SELECT id, session_id, timestamp, sub_function, request_id, request_prompt,
                   action, classification_kind, classification_tier, actor, outcome
            FROM gated_decision_log
            WHERE project_id = ? AND timestamp >= ? AND timestamp <= ?
            ORDER BY timestamp ASC;
            """,
            bindings: [
                .text(project.rawValue),
                .double(start.timeIntervalSince1970),
                .double(end.timeIntervalSince1970)
            ]
        )
        return try rows.map { try Self.storedEntry(from: $0, project: project) }
    }

    /// Every entry for one session, oldest first — what a resume or an export
    /// joins against a stored ``SessionTranscriptEntry/toolCall(id:name:targets:)``
    /// by its `id` to recover that call's resolved outcome, rather than a
    /// second, duplicated write path for approvals reaching this log already
    /// records.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
    public func entries(project: ProjectIdentifier, sessionID: UUID) async throws -> [StoredGatedDecisionEntry] {
        let rows = try await database.query(
            """
            SELECT id, session_id, timestamp, sub_function, request_id, request_prompt,
                   action, classification_kind, classification_tier, actor, outcome
            FROM gated_decision_log
            WHERE project_id = ? AND session_id = ?
            ORDER BY timestamp ASC;
            """,
            bindings: [.text(project.rawValue), .text(sessionID.uuidString)]
        )
        return try rows.map { try Self.storedEntry(from: $0, project: project) }
    }

    private enum EntryColumn: Int, CaseIterable {
        case id, sessionID, timestamp, subFunction, requestID, requestPrompt
        case action, classificationKind, classificationTier, actor, outcome
    }

    private static func storedEntry(
        from row: [DatabaseValue],
        project: ProjectIdentifier
    ) throws -> StoredGatedDecisionEntry {
        guard
            row.count == EntryColumn.allCases.count,
            case let .int(id) = row[EntryColumn.id.rawValue],
            case let .text(sessionIDText) = row[EntryColumn.sessionID.rawValue],
            let sessionID = UUID(uuidString: sessionIDText),
            case let .double(timestampEpoch) = row[EntryColumn.timestamp.rawValue],
            case let .text(subFunctionRaw) = row[EntryColumn.subFunction.rawValue],
            let subFunction = SubFunction(rawValue: subFunctionRaw),
            case let .text(requestID) = row[EntryColumn.requestID.rawValue],
            case let .text(requestPrompt) = row[EntryColumn.requestPrompt.rawValue],
            case let .text(actionRaw) = row[EntryColumn.action.rawValue],
            case let .text(classificationKind) = row[EntryColumn.classificationKind.rawValue],
            case let .text(actorRaw) = row[EntryColumn.actor.rawValue],
            let actor = SafeguardsDecisionActor(rawValue: actorRaw),
            case let .text(outcomeRaw) = row[EntryColumn.outcome.rawValue],
            let outcome = AgentPermissionDecision(rawValue: outcomeRaw),
            let classification = Self.classification(
                kind: classificationKind,
                tierColumn: row[EntryColumn.classificationTier.rawValue]
            )
        else {
            throw GatedDecisionLogStoreError.malformedRow
        }
        return StoredGatedDecisionEntry(
            id: Int(id),
            project: project,
            sessionID: sessionID,
            timestamp: Date(timeIntervalSince1970: timestampEpoch),
            subFunction: subFunction,
            requestID: requestID,
            requestPrompt: requestPrompt,
            action: SafeguardsActionType(rawValue: actionRaw),
            classification: classification,
            actor: actor,
            outcome: outcome
        )
    }

    private static func classification(
        kind: String,
        tierColumn: DatabaseValue
    ) -> SafeguardsClassification? {
        switch kind {
        case "refused":
            .refused
        case "tier":
            tier(from: tierColumn).map(SafeguardsClassification.tier)
        default:
            nil
        }
    }

    private static func tier(from column: DatabaseValue) -> SafeguardsTier? {
        guard case let .text(raw) = column else { return nil }
        return SafeguardsTier(rawValue: raw)
    }
}

/// A row this store wrote itself failed to decode back — a schema/code
/// mismatch, never an expected runtime condition.
public enum GatedDecisionLogStoreError: Error, Equatable, Sendable {
    case malformedRow
}
