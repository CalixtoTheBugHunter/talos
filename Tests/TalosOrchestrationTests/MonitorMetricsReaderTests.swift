import Foundation
import TalosAdapters
import TalosOrchestration
import TalosPersistence
import TalosProjectLibrary
import Testing

/// The Monitor "is readable by the guidelines so Talos can identify problems in
/// its own use and self-improve" — exposed as project-scoped aggregates.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen
@Suite("Monitor metrics reader")
struct MonitorMetricsReaderTests {
    private static let projectA = ProjectIdentifier(rawValue: "project-a")
    private static let projectB = ProjectIdentifier(rawValue: "project-b")
    private static let start = Date(timeIntervalSince1970: 0)
    private static let end = Date(timeIntervalSince1970: 10000)

    private static func store() async throws -> SQLiteSessionRecordStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("test.sqlite", isDirectory: false)
        let database = try await Database(url: url, migrations: [
            SessionRecordsSchema.migration,
            SessionTranscriptSchema.migration,
            SessionRecordsSchema.cacheTokenColumnsMigration,
            SessionRecordsSchema.overheadSourcesMigration
        ])
        return SQLiteSessionRecordStore(database: database)
    }

    private static func measured(input: Int, output: Int) -> TokenReport {
        .measured(TokenCounts(input: input, output: output), model: "test-model")
    }

    private static func record(
        project: ProjectIdentifier = projectA,
        outcome: SessionOutcome,
        duration: TimeInterval = 10,
        toolCalls: Int = 1,
        injected: InjectedTokens? = nil
    ) -> SessionRecord {
        SessionRecord(
            id: UUID(),
            project: project,
            subFunction: .assistant,
            agentName: "claude-code",
            outcome: outcome,
            startedAt: Date(timeIntervalSince1970: 1000),
            duration: duration,
            toolCallCount: toolCalls,
            approvalCount: 2,
            denialCount: 1,
            retryCount: 1,
            tokenOverheadRatio: 0,
            injectedTokens: injected
        )
    }

    @Test("Metrics are the totals across the project's sessions")
    func metricsAreTotals() async throws {
        let store = try await Self.store()
        await store.write(Self.record(
            outcome: .succeeded(Self.measured(input: 100, output: 50)),
            duration: 10,
            toolCalls: 3
        ))
        await store.write(Self.record(
            outcome: .succeeded(Self.measured(input: 200, output: 25)),
            duration: 5,
            toolCalls: 4
        ))

        let metrics = try await MonitorMetricsReader(source: store)
            .metrics(project: Self.projectA, from: Self.start, to: Self.end)

        #expect(metrics.sessionCount == 2)
        #expect(metrics.totalDuration == 15)
        #expect(metrics.toolCallCount == 7)
        #expect(metrics.approvalCount == 4)
        #expect(metrics.denialCount == 2)
        #expect(metrics.retryCount == 2)
        #expect(metrics.inputTokens == 300)
        #expect(metrics.outputTokens == 75)
    }

    /// "`Denied` and `Stopped` are excluded from the rate, and the exclusion is
    /// counted where the figure appears."
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-task-outcome-is-classified
    @Test("Denied and stopped sessions are excluded from the success rate and counted")
    func deniedAndStoppedAreExcludedAndCounted() async throws {
        let store = try await Self.store()
        let report = Self.measured(input: 10, output: 10)
        await store.write(Self.record(outcome: .succeeded(report)))
        await store.write(Self.record(outcome: .failed(reason: "exit 1", tokenReport: report)))
        await store.write(Self.record(outcome: .denied(report)))
        await store.write(Self.record(outcome: .stopped(report)))

        let metrics = try await MonitorMetricsReader(source: store)
            .metrics(project: Self.projectA, from: Self.start, to: Self.end)

        #expect(metrics.outcomes.overall.fraction == 0.5)
        #expect(metrics.outcomes.overall.ratedCount == 2)
        #expect(metrics.outcomes.overall.excludedCount == 2)
    }

    /// "A token count Talos cannot parse is absent and named. It is never
    /// repaired, inferred, or shown as zero."
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#when-the-log-format-changes
    @Test("A session with no token count is counted as unavailable, never as zero tokens")
    func unavailableTokenCountIsCountedNotZeroed() async throws {
        let store = try await Self.store()
        let injected = InjectedTokens(bySource: [.guideline: 5], framing: 1)
        await store.write(Self.record(outcome: .succeeded(Self.measured(input: 100, output: 20)), injected: injected))
        await store.write(Self.record(
            outcome: .succeeded(.unavailable(TokenUsageUnavailable(reason: .unrecognizedFormat))),
            injected: injected
        ))

        let metrics = try await MonitorMetricsReader(source: store)
            .metrics(project: Self.projectA, from: Self.start, to: Self.end)

        #expect(metrics.measuredTokenSessionCount == 1)
        #expect(metrics.unavailableTokenSessionCount == 1)
        #expect(metrics.inputTokens == 100)
        #expect(metrics.overhead.measuredCount == 1)
        #expect(metrics.overhead.excludedCount == 1)
    }

    @Test("Metrics are project-scoped: another project's sessions never appear")
    func metricsAreProjectScoped() async throws {
        let store = try await Self.store()
        await store.write(Self.record(project: Self.projectA, outcome: .succeeded(Self.measured(input: 10, output: 1))))
        await store.write(Self.record(
            project: Self.projectB,
            outcome: .succeeded(Self.measured(input: 999, output: 999))
        ))
        await store.write(Self.record(project: Self.projectB, outcome: .failed(
            reason: "exit 1", tokenReport: Self.measured(input: 1, output: 1)
        )))

        let metrics = try await MonitorMetricsReader(source: store)
            .metrics(project: Self.projectA, from: Self.start, to: Self.end)

        #expect(metrics.sessionCount == 1)
        #expect(metrics.inputTokens == 10)
        #expect(metrics.outcomes.overall.failed == 0)
    }
}
