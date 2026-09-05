import Foundation
import TalosAdapters
@testable import TalosOrchestration
import TalosPersistence
import TalosProjectLibrary
import Testing

/// Asserts the transcript and resume-token columns
/// ``SessionTranscriptSchema`` adds: a written transcript reads back in
/// order, a resume token round-trips, deleting a session cascades its
/// transcript rows too, and a secret-shaped string never reaches disk.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
@Suite("SQLite session transcript")
struct SQLiteSessionRecordStoreTranscriptTests {
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
        transcript: [SessionTranscriptEntry] = [],
        resumeToken: String? = nil
    ) -> SessionRecord {
        SessionRecord(
            id: id,
            project: project,
            subFunction: .assistant,
            agentName: "claude-code",
            outcome: .succeeded(.measured(TokenCounts(input: 10, output: 5), model: "test-model")),
            startedAt: Date(timeIntervalSince1970: 1000),
            duration: 12,
            toolCallCount: 1,
            approvalCount: 0,
            denialCount: 0,
            retryCount: 0,
            tokenOverheadRatio: 0.1,
            transcript: transcript,
            resumeToken: resumeToken
        )
    }

    @Test("A written transcript reads back in arrival order")
    func transcriptReadsBackInOrder() async throws {
        let database = try await Self.temporaryDatabase()
        let store = SQLiteSessionRecordStore(database: database)
        let project = ProjectIdentifier(rawValue: "p1")
        let record = Self.makeRecord(project: project, transcript: [
            .output("Reading the file.\n"),
            .toolCall(id: "t1", name: "Read", targets: ["README.md", "Package.swift"]),
            .output("Done.\n")
        ])

        await store.write(record)
        let found = try await store.transcriptEntries(project: project, sessionID: record.id)

        #expect(found == [
            .output("Reading the file.\n"),
            .toolCall(id: "t1", name: "Read", targets: ["README.md", "Package.swift"]),
            .output("Done.\n")
        ])
    }

    @Test("A written resume token reads back on the stored record")
    func resumeTokenReadsBack() async throws {
        let database = try await Self.temporaryDatabase()
        let store = SQLiteSessionRecordStore(database: database)
        let project = ProjectIdentifier(rawValue: "p1")
        let record = Self.makeRecord(project: project, resumeToken: "claude-session-42")

        await store.write(record)
        let found = try await store.records(
            project: project,
            from: Date(timeIntervalSince1970: 0),
            to: Date(timeIntervalSince1970: 100_000)
        )

        #expect(found.first?.resumeToken == "claude-session-42")
    }

    @Test("A session with no resume token reads back nil, not an empty string")
    func absentResumeTokenReadsBackAsNil() async throws {
        let database = try await Self.temporaryDatabase()
        let store = SQLiteSessionRecordStore(database: database)
        let project = ProjectIdentifier(rawValue: "p1")
        let record = Self.makeRecord(project: project)

        await store.write(record)
        let found = try await store.records(
            project: project,
            from: Date(timeIntervalSince1970: 0),
            to: Date(timeIntervalSince1970: 100_000)
        )

        #expect(found.first?.resumeToken == nil)
    }

    /// "Deletion is real deletion, including the associated token records" —
    /// the same guarantee extends to the transcript.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#chat-history-management
    @Test("Deleting a session removes its transcript entries")
    func deletingASessionRemovesItsTranscriptEntries() async throws {
        let database = try await Self.temporaryDatabase()
        let store = SQLiteSessionRecordStore(database: database)
        let record = Self.makeRecord(transcript: [.output("hello")])

        await store.write(record)
        #expect(try await database.rowCount(table: "session_transcript_entries") == 1)

        try await store.delete(record.id)

        #expect(try await database.rowCount(table: "session_transcript_entries") == 0)
    }

    /// "Export never includes secret values" traces to the exporter, but the
    /// same rule already governs every call site that logs content Talos did
    /// not author — so a secret-shaped string is redacted before it ever
    /// reaches disk, not only when it happens to be exported later.
    @Test("A secret-shaped string in transcript output is redacted before it reaches disk")
    func secretShapedOutputIsRedactedAtWrite() async throws {
        let database = try await Self.temporaryDatabase()
        let store = SQLiteSessionRecordStore(database: database)
        let project = ProjectIdentifier(rawValue: "p1")
        let secret = "sk-ant-\(String(repeating: "a", count: 20))"
        let record = Self.makeRecord(project: project, transcript: [.output("Key: \(secret)")])

        await store.write(record)
        let found = try await store.transcriptEntries(project: project, sessionID: record.id)

        guard case let .output(text) = found.first else {
            Issue.record("Expected one output entry")
            return
        }
        #expect(!text.contains(secret))
        #expect(text.contains("<redacted>"))
    }

    /// The same redaction applies to a tool call's own name and targets — an
    /// agent could announce a call whose target embeds a credential-shaped
    /// path or argument.
    @Test("A secret-shaped tool-call target is redacted before it reaches disk")
    func secretShapedToolCallTargetIsRedactedAtWrite() async throws {
        let database = try await Self.temporaryDatabase()
        let store = SQLiteSessionRecordStore(database: database)
        let project = ProjectIdentifier(rawValue: "p1")
        let secret = "AKIA\(String(repeating: "A", count: 16))"
        let record = Self.makeRecord(project: project, transcript: [
            .toolCall(id: "t1", name: "Bash", targets: ["export KEY=\(secret)"])
        ])

        await store.write(record)
        let found = try await store.transcriptEntries(project: project, sessionID: record.id)

        guard case let .toolCall(_, _, targets) = found.first else {
            Issue.record("Expected one tool-call entry")
            return
        }
        #expect(!targets.joined().contains(secret))
    }

    /// Stands in for "survives app restart": a fresh `Database` opened on the
    /// same file sees every row a previous instance wrote, since nothing here
    /// is held only in memory. "Resume across app restart works, since
    /// records are in SQLite."
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
    @Test("The transcript and the resume token survive the database being closed and reopened")
    func transcriptAndResumeTokenSurviveReopeningTheDatabase() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("test.sqlite", isDirectory: false)
        let migrations = [SessionRecordsSchema.migration, SessionTranscriptSchema.migration]
        let database = try await Database(url: url, migrations: migrations)
        let store = SQLiteSessionRecordStore(database: database)
        let project = ProjectIdentifier(rawValue: "p1")
        let record = Self.makeRecord(
            project: project,
            transcript: [.output("Reading the file tree.\n"), .toolCall(id: "t1", name: "Read", targets: ["a.swift"])],
            resumeToken: "claude-session-before-restart"
        )
        await store.write(record)

        let reopened = try await Database(url: url, migrations: migrations)
        let reopenedStore = SQLiteSessionRecordStore(database: reopened)

        let transcript = try await reopenedStore.transcriptEntries(project: project, sessionID: record.id)
        let found = try await reopenedStore.records(
            project: project,
            from: Date(timeIntervalSince1970: 0),
            to: Date(timeIntervalSince1970: 100_000)
        )

        let expectedTranscript: [SessionTranscriptEntry] = [
            .output("Reading the file tree.\n"),
            .toolCall(id: "t1", name: "Read", targets: ["a.swift"])
        ]
        #expect(transcript == expectedTranscript)
        #expect(found.first?.resumeToken == "claude-session-before-restart")
    }
}
