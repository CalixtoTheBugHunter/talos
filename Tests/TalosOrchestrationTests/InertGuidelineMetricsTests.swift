import Foundation
import TalosOrchestration
import TalosProjectLibrary
import Testing

/// Monitor metrics are exposed for guidelines but inert at MVP:
/// `.talos/guidelines/self-improver.md` "is **present but inert** until
/// Self-improver ships", and no context part assembles Monitor data.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Sub-function-Self-improver#guidelines
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
@Suite("Inert guideline pulls no Monitor metrics")
struct InertGuidelineMetricsTests {
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

    private static func assemble(_ guideline: GuidelineDocument) -> AssembledContext? {
        let input = ContextAssemblyInput(
            intent: makeTestIntent(project: .generate(), requestingSubFunction: .selfImprover),
            guideline: guideline,
            safeguards: makeTestSafeguards(),
            connectors: ConnectorsManifest(connectors: [])
        )
        guard case let .assembled(context) = makeTestAssembler().assemble(input) else { return nil }
        return context
    }

    @Test("The shipped inert Self-improver guideline assembles no metric data")
    func shippedInertGuidelineAssemblesNoMetrics() throws {
        let context = try #require(Self.assemble(Self.scaffoldedSelfImproverGuideline()))

        #expect(context.includedParts.map(\.kind) == [.guideline, .safeguards])
        #expect(context.unavailableParts.isEmpty)
    }

    @Test("A guideline asking for 'monitor' context still assembles no metric data")
    func requestingMonitorContextAssemblesNoMetrics() throws {
        let guideline = makeTestGuideline(subFunction: .selfImprover, context: ["monitor"], tokenCeiling: 10000)

        let context = try #require(Self.assemble(guideline))

        #expect(ContextPartKind(rawValue: "monitor") == nil)
        #expect(context.includedParts.map(\.kind) == [.guideline, .safeguards])
    }
}
