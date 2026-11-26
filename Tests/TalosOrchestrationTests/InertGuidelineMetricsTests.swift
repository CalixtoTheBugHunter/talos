import Foundation
import TalosAdapters
import TalosOrchestration
import TalosPersistence
import TalosProjectLibrary
import Testing

/// Monitor metrics are exposed for guidelines but inert at MVP:
/// `.talos/guidelines/self-improver.md` "is **present but inert** until
/// Self-improver ships", and no context part assembles Monitor data.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Sub-function-Self-improver#guidelines
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
@Suite("Inert guideline pulls no Monitor metrics")
struct InertGuidelineMetricsTests {
    private static let canaryModel = "monitor-metrics-canary-model"

    private static func scaffoldedSelfImproverGuideline() throws -> GuidelineDocument {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git", isDirectory: true), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try ProjectLibraryScaffolder.scaffold(projectRoot: root)
        let file = root.appendingPathComponent(".talos/guidelines/self-improver.md")
        return try GuidelineDocumentParser.parse(
            contents: String(contentsOf: file, encoding: .utf8),
            subFunction: .selfImprover,
            file: file.path
        )
    }

    /// Writes a session whose model name is a canary, so any metric data that
    /// reached the prompt would be findable in the assembled text.
    private static func storeWithRecordedSession(project: ProjectIdentifier) async throws -> SQLiteSessionRecordStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("test.sqlite", isDirectory: false)
        let store = try await SQLiteSessionRecordStore(database: Database(url: url, migrations: [
            SessionRecordsSchema.migration,
            SessionTranscriptSchema.migration,
            SessionRecordsSchema.cacheTokenColumnsMigration,
            SessionRecordsSchema.overheadSourcesMigration
        ]))
        await store.write(SessionRecord(
            id: UUID(),
            project: project,
            subFunction: .assistant,
            agentName: "claude-code",
            outcome: .succeeded(.measured(TokenCounts(input: 4242, output: 4242), model: canaryModel)),
            startedAt: Date(timeIntervalSince1970: 1000),
            duration: 10,
            toolCallCount: 1,
            approvalCount: 0,
            denialCount: 0,
            retryCount: 0,
            tokenOverheadRatio: 0
        ))
        return store
    }

    private static func assemble(_ guideline: GuidelineDocument, project: ProjectIdentifier) -> AssembledContext? {
        let input = ContextAssemblyInput(
            intent: makeTestIntent(project: project, requestingSubFunction: .selfImprover),
            guideline: guideline,
            safeguards: makeTestSafeguards(),
            connectors: ConnectorsManifest(connectors: [])
        )
        guard case let .assembled(context) = makeTestAssembler().assemble(input) else { return nil }
        return context
    }

    @Test("The shipped inert Self-improver guideline assembles no metric data")
    func shippedInertGuidelineAssemblesNoMetrics() async throws {
        let project = ProjectIdentifier.generate()
        let store = try await Self.storeWithRecordedSession(project: project)
        let metrics = try await MonitorMetricsReader(source: store)
            .metrics(project: project, from: .distantPast, to: .distantFuture)
        #expect(metrics.sessionCount == 1)

        let context = try #require(Self.assemble(Self.scaffoldedSelfImproverGuideline(), project: project))

        #expect(context.includedParts.map(\.kind) == [.guideline, .safeguards])
        #expect(context.unavailableParts.isEmpty)
        #expect(!context.includedParts.contains { $0.text.contains(Self.canaryModel) })
    }

    @Test("A guideline asking for 'monitor' context still assembles no metric data")
    func requestingMonitorContextAssemblesNoMetrics() async throws {
        let project = ProjectIdentifier.generate()
        _ = try await Self.storeWithRecordedSession(project: project)
        let guideline = makeTestGuideline(subFunction: .selfImprover, context: ["monitor"], tokenCeiling: 10000)

        let context = try #require(Self.assemble(guideline, project: project))

        #expect(ContextPartKind(rawValue: "monitor") == nil)
        #expect(context.includedParts.map(\.kind) == [.guideline, .safeguards])
        #expect(!context.includedParts.contains { $0.text.contains(Self.canaryModel) })
    }
}
