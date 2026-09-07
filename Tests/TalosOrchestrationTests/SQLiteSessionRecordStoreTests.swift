import Foundation
import TalosAdapters
@testable import TalosOrchestration
import TalosPersistence
import TalosProjectLibrary
import Testing

/// Records are queryable by project and by time range for the Monitor
/// Screen, and deleting a session really deletes it and its token records.
@Suite("SQLite session record store")
struct SQLiteSessionRecordStoreTests {
    private static func temporaryDatabase() async throws -> Database {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("test.sqlite", isDirectory: false)
        let migrations = [SessionRecordsSchema.migration, SessionTranscriptSchema.migration]
        return try await Database(url: url, migrations: migrations)
    }

    private static func makeRecord(
        id: UUID = UUID(),
        project: ProjectIdentifier = ProjectIdentifier(rawValue: "p1"),
        startedAt: Date = Date(timeIntervalSince1970: 1000),
        outcome: SessionOutcome = .succeeded(.measured(TokenCounts(input: 10, output: 5), model: "test-model"))
    ) -> SessionRecord {
        SessionRecord(
            id: id,
            project: project,
            subFunction: .assistant,
            agentName: "claude-code",
            outcome: outcome,
            startedAt: startedAt,
            duration: 12,
            toolCallCount: 3,
            approvalCount: 2,
            denialCount: 1,
            retryCount: 0,
            tokenOverheadRatio: 0.25
        )
    }

    @Test("A written record is queryable by its project and time range")
    func writtenRecordIsQueryableByProjectAndTimeRange() async throws {
        let database = try await Self.temporaryDatabase()
        let store = SQLiteSessionRecordStore(database: database)
        let project = ProjectIdentifier(rawValue: "p1")
        let record = Self.makeRecord(project: project, startedAt: Date(timeIntervalSince1970: 1000))

        await store.write(record)

        let found = try await store.records(
            project: project,
            from: Date(timeIntervalSince1970: 500),
            to: Date(timeIntervalSince1970: 1500)
        )

        #expect(found.count == 1)
        #expect(found.first?.id == record.id)
        #expect(found.first?.project == project)
        #expect(found.first?.subFunction == .assistant)
        #expect(found.first?.agentName == "claude-code")
        #expect(found.first?.outcome == .succeeded)
        #expect(found.first?.toolCallCount == 3)
        #expect(found.first?.approvalCount == 2)
        #expect(found.first?.denialCount == 1)
        #expect(found.first?.tokenOverheadRatio == 0.25)
    }

    @Test("A record outside the queried time range is not returned")
    func recordOutsideTimeRangeIsExcluded() async throws {
        let database = try await Self.temporaryDatabase()
        let store = SQLiteSessionRecordStore(database: database)
        let project = ProjectIdentifier(rawValue: "p1")
        await store.write(Self.makeRecord(project: project, startedAt: Date(timeIntervalSince1970: 10000)))

        let found = try await store.records(
            project: project,
            from: Date(timeIntervalSince1970: 0),
            to: Date(timeIntervalSince1970: 100)
        )

        #expect(found.isEmpty)
    }

    @Test("A record from a different project is not returned")
    func recordFromAnotherProjectIsExcluded() async throws {
        let database = try await Self.temporaryDatabase()
        let store = SQLiteSessionRecordStore(database: database)
        await store.write(Self.makeRecord(project: ProjectIdentifier(rawValue: "other-project")))

        let found = try await store.records(
            project: ProjectIdentifier(rawValue: "p1"),
            from: Date(timeIntervalSince1970: 0),
            to: Date(timeIntervalSince1970: 100_000)
        )

        #expect(found.isEmpty)
    }

    /// "Deletion is real deletion, including the associated token records."
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#chat-history-management
    @Test("Deleting a session removes it and its token records")
    func deletingASessionRemovesItsTokenRecords() async throws {
        let database = try await Self.temporaryDatabase()
        let store = SQLiteSessionRecordStore(database: database)
        let record = Self.makeRecord()

        await store.write(record)
        #expect(try await database.rowCount(table: "session_records") == 1)
        #expect(try await database.rowCount(table: "session_token_records") == 1)

        try await store.delete(record.id)

        #expect(try await database.rowCount(table: "session_records") == 0)
        #expect(try await database.rowCount(table: "session_token_records") == 0)
    }

    /// A session that never launched an agent — a context-assembly failure
    /// or a pre-check denial — has no token usage to report, so it writes no
    /// `session_token_records` row at all.
    @Test("A session with no token report writes no token record")
    func noTokenReportWritesNoTokenRecord() async throws {
        let database = try await Self.temporaryDatabase()
        let store = SQLiteSessionRecordStore(database: database)
        let outcome = SessionOutcome.safeguardsPreCheckDenied(reason: "Production deploys need a human.")

        await store.write(Self.makeRecord(outcome: outcome))

        #expect(try await database.rowCount(table: "session_records") == 1)
        #expect(try await database.rowCount(table: "session_token_records") == 0)
    }

    @Test("An unavailable token report is stored with its reason, not as zero")
    func unavailableTokenReportIsStoredWithItsReason() async throws {
        let database = try await Self.temporaryDatabase()
        let store = SQLiteSessionRecordStore(database: database)
        let outcome = SessionOutcome.failed(
            reason: "The agent could not be launched.",
            tokenReport: .unavailable(TokenUsageUnavailable(reason: .notReported, agentVersion: "1.2.3"))
        )

        await store.write(Self.makeRecord(outcome: outcome))

        let rows = try await database.query(
            "SELECT input_tokens, unavailable_reason, agent_version FROM session_token_records;"
        )
        #expect(rows == [[.null, .text("notReported"), .text("1.2.3")]])
    }
}
