import Foundation
import TalosAdapters
import TalosCore
@testable import TalosOrchestration
import TalosPersistence
import TalosProjectLibrary
import TalosSafeguards
import Testing

/// "Every gated decision is logged with the actor, the action, the tier, and
/// the outcome"; a refused type is logged as refused, not as a denial at some
/// tier; an allowlisted pass names the allowlist as the actor; the log is
/// append-only; entries carry a timestamp and the project and session id;
/// secret values never appear in the log though secret access does; and the
/// log survives being reopened, standing in for surviving an app restart.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
@Suite("SQLite gated decision log")
struct SQLiteGatedDecisionLogTests {
    private static func temporaryDatabase() async throws -> (Database, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("test.sqlite", isDirectory: false)
        return try await (Database(url: url, migrations: [GatedDecisionLogSchema.migration]), url)
    }

    private static func makeEntry(
        project: ProjectIdentifier = ProjectIdentifier(rawValue: "p1"),
        sessionID: UUID = UUID(),
        timestamp: Date = Date(timeIntervalSince1970: 1000),
        subFunction: SubFunction = .automator,
        requestID: String = "r1",
        requestPrompt: String = "Delete 4 files in Sources/",
        decision: SafeguardsDecision = SafeguardsDecision(
            outcome: .denied,
            action: .fileDelete,
            classification: .tier(.irreversible),
            actor: .user
        )
    ) -> GatedDecisionEntry {
        GatedDecisionEntry(
            project: project,
            sessionID: sessionID,
            timestamp: timestamp,
            subFunction: subFunction,
            request: AgentPermissionRequest(id: requestID, prompt: requestPrompt, toolName: decision.action.rawValue),
            decision: decision
        )
    }

    @Test("A recorded entry is readable back with the actor, the action, the tier, and the outcome")
    func recordedEntryIsReadableBackWithAllFourFields() async throws {
        let (database, _) = try await Self.temporaryDatabase()
        let log = SQLiteGatedDecisionLog(database: database)
        let project = ProjectIdentifier(rawValue: "p1")
        let sessionID = UUID()
        let entry = Self.makeEntry(project: project, sessionID: sessionID, timestamp: Date(timeIntervalSince1970: 1000))

        await log.record(entry)

        let found = try await log.entries(
            project: project,
            from: Date(timeIntervalSince1970: 0),
            to: Date(timeIntervalSince1970: 2000)
        )

        #expect(found.count == 1)
        #expect(found.first?.project == project)
        #expect(found.first?.sessionID == sessionID)
        #expect(found.first?.timestamp == Date(timeIntervalSince1970: 1000))
        #expect(found.first?.subFunction == .automator)
        #expect(found.first?.requestID == "r1")
        #expect(found.first?.requestPrompt == "Delete 4 files in Sources/")
        #expect(found.first?.action == .fileDelete)
        #expect(found.first?.classification == .tier(.irreversible))
        #expect(found.first?.actor == .user)
        #expect(found.first?.outcome == .denied)
    }

    /// "Refused is not a tier" — a refused action's classification round-trips
    /// as `.refused`, never collapsed into a tiered denial.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#refused--not-a-tier
    @Test("A refused decision is stored and read back as refused, not as a tiered denial")
    func refusedDecisionRoundTripsAsRefused() async throws {
        let (database, _) = try await Self.temporaryDatabase()
        let log = SQLiteGatedDecisionLog(database: database)
        let project = ProjectIdentifier(rawValue: "p1")
        let entry = Self.makeEntry(
            project: project,
            decision: SafeguardsDecision(
                outcome: .denied,
                action: .configSafeguardsWrite,
                classification: .refused,
                actor: .talos
            )
        )

        await log.record(entry)

        let found = try await log.entries(project: project, from: .distantPast, to: .distantFuture)

        #expect(found.first?.action == .configSafeguardsWrite)
        #expect(found.first?.classification == .refused)
        #expect(found.first?.actor == .talos)
    }

    /// "A decision made by an allowlist is still a gated decision."
    @Test("An allowlisted pass is stored and read back with the allowlist as the actor")
    func allowlistedPassRoundTripsWithAllowlistActor() async throws {
        let (database, _) = try await Self.temporaryDatabase()
        let log = SQLiteGatedDecisionLog(database: database)
        let project = ProjectIdentifier(rawValue: "p1")
        let entry = Self.makeEntry(
            project: project,
            decision: SafeguardsDecision(
                outcome: .allowed,
                action: .fileWrite,
                classification: .tier(.write),
                actor: .allowlist
            )
        )

        await log.record(entry)

        let found = try await log.entries(project: project, from: .distantPast, to: .distantFuture)

        #expect(found.first?.outcome == .allowed)
        #expect(found.first?.actor == .allowlist)
    }

    @Test("Two recorded entries both persist, in the order they were recorded — the log appends rather than overwrites")
    func twoEntriesBothPersistInOrder() async throws {
        let (database, _) = try await Self.temporaryDatabase()
        let log = SQLiteGatedDecisionLog(database: database)
        let project = ProjectIdentifier(rawValue: "p1")
        let first = Self.makeEntry(project: project, timestamp: Date(timeIntervalSince1970: 1000), requestID: "r1")
        let second = Self.makeEntry(project: project, timestamp: Date(timeIntervalSince1970: 2000), requestID: "r2")

        await log.record(first)
        await log.record(second)

        #expect(try await database.rowCount(table: "gated_decision_log") == 2)
        let found = try await log.entries(project: project, from: .distantPast, to: .distantFuture)
        #expect(found.map(\.requestID) == ["r1", "r2"])
    }

    /// What a resume or an export joins a stored ``SessionTranscriptEntry``
    /// against, by call id — never a duplicated write path for what this log
    /// already records.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
    @Test("Entries scoped to one session exclude another session's, even in the same project")
    func sessionScopedQueryExcludesAnotherSessionsEntries() async throws {
        let (database, _) = try await Self.temporaryDatabase()
        let log = SQLiteGatedDecisionLog(database: database)
        let project = ProjectIdentifier(rawValue: "p1")
        let sessionID = UUID()
        let otherSessionID = UUID()
        await log.record(Self.makeEntry(project: project, sessionID: sessionID, requestID: "r1"))
        await log.record(Self.makeEntry(project: project, sessionID: otherSessionID, requestID: "r2"))

        let found = try await log.entries(project: project, sessionID: sessionID)

        #expect(found.map(\.requestID) == ["r1"])
    }

    @Test("A record from a different project is not returned")
    func recordFromAnotherProjectIsExcluded() async throws {
        let (database, _) = try await Self.temporaryDatabase()
        let log = SQLiteGatedDecisionLog(database: database)
        await log.record(Self.makeEntry(project: ProjectIdentifier(rawValue: "other-project")))

        let found = try await log.entries(
            project: ProjectIdentifier(rawValue: "p1"),
            from: .distantPast,
            to: .distantFuture
        )

        #expect(found.isEmpty)
    }

    /// "Secret values never appear in the log, though secret access does" —
    /// the CLI's own wording is withheld for a secret action type, while the
    /// action, actor, and outcome still name exactly what was attempted.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
    @Test(
        "A secret action's prompt is never persisted, though the access itself is",
        arguments: [SafeguardsActionType.secretRead, .secretWrite, .secretSend]
    )
    func secretActionPromptIsRedactedButAccessIsRecorded(action: SafeguardsActionType) async throws {
        let (database, _) = try await Self.temporaryDatabase()
        let log = SQLiteGatedDecisionLog(database: database)
        let project = ProjectIdentifier(rawValue: "p1")
        let secretValue = "sk-live-super-secret-value"
        let entry = Self.makeEntry(
            project: project,
            requestPrompt: "Send \(secretValue) to the deploy target",
            decision: SafeguardsDecision(
                outcome: .denied,
                action: action,
                classification: .tier(.irreversible),
                actor: .user
            )
        )

        await log.record(entry)

        let found = try await log.entries(project: project, from: .distantPast, to: .distantFuture)

        #expect(found.first?.action == action)
        #expect(found.first?.outcome == .denied)
        #expect(found.first?.requestPrompt.contains(secretValue) == false)

        // The raw table, not just the typed row, carries no trace of the value —
        // the redaction happens before the write, not only on the read path.
        let rawPrompts = try await database.query("SELECT request_prompt FROM gated_decision_log;")
        for row in rawPrompts {
            if case let .text(text) = row[0] {
                #expect(!text.contains(secretValue))
            }
        }
    }

    @Test("A non-secret action's prompt is persisted verbatim")
    func nonSecretActionPromptIsPersistedVerbatim() async throws {
        let (database, _) = try await Self.temporaryDatabase()
        let log = SQLiteGatedDecisionLog(database: database)
        let project = ProjectIdentifier(rawValue: "p1")
        let entry = Self.makeEntry(project: project, requestPrompt: "Delete 4 files in Sources/")

        await log.record(entry)

        let found = try await log.entries(project: project, from: .distantPast, to: .distantFuture)
        #expect(found.first?.requestPrompt == "Delete 4 files in Sources/")
    }

    /// Stands in for "survives app restart": a fresh `Database` opened on the
    /// same file sees every row a previous instance wrote, since nothing here
    /// is held only in memory.
    @Test("Entries survive the database being closed and reopened at the same location")
    func entriesSurviveReopeningTheDatabase() async throws {
        let (database, url) = try await Self.temporaryDatabase()
        let log = SQLiteGatedDecisionLog(database: database)
        let project = ProjectIdentifier(rawValue: "p1")
        await log.record(Self.makeEntry(project: project, requestID: "before-restart"))

        let reopened = try await Database(url: url, migrations: [GatedDecisionLogSchema.migration])
        let reopenedLog = SQLiteGatedDecisionLog(database: reopened)

        let found = try await reopenedLog.entries(project: project, from: .distantPast, to: .distantFuture)
        #expect(found.map(\.requestID) == ["before-restart"])
    }

    /// "The log is append-only — no code path updates or deletes an entry."
    /// `record`/`entries` are the only public methods, but that alone is not
    /// checkable at the call site, so this greps the definition itself for
    /// the two SQL statement shapes that would violate it — the same
    /// structural-absence technique `AllowlistStoreWriteReachabilityTests`
    /// uses for its own file.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
    @Test("SQLiteGatedDecisionLog contains no UPDATE or DELETE against gated_decision_log")
    func definitionContainsNoUpdateOrDelete() throws {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                break
            }
        }
        let definitionFile = url
            .appendingPathComponent("Sources/TalosOrchestration/SQLiteGatedDecisionLog.swift")
        let source = try String(contentsOf: definitionFile, encoding: .utf8)

        #expect(!source.contains("UPDATE gated_decision_log"))
        #expect(!source.contains("DELETE FROM gated_decision_log"))
    }
}
