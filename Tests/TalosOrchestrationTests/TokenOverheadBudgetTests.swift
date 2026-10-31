import Foundation
import TalosAdapters
import TalosOrchestration
import TalosProjectLibrary
import Testing

/// The CI assertion behind the < 5% Talos-added token overhead release gate:
/// a representative session, assembled by the real ``ContextAssembler`` from
/// the guideline and Safeguards copy Talos actually ships, and measured by the
/// same arithmetic the Monitor uses, stays under the budget. `perf-budget`
/// runs this suite by name.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-token-overhead-is-computed
@Suite("Token overhead budget")
struct TokenOverheadBudgetTests {
    // The droppable sources are fakes, so their sizes are stated assumptions:
    // typical mid-project excerpts, well inside the shipped 4000-token ceiling.
    private static let boardTokens = 400
    private static let memoriesTokens = 250

    /// A multi-step Automator turn as the agent would report it: it reads files,
    /// runs tools, and writes a change. Cache reads dominate, as they do in
    /// long agent sessions. The budget holds for this session size and larger.
    private static let reportedSession = TokenCounts(
        input: 8000, output: 6000, cacheCreation: 6000, cacheRead: 40000
    )

    private static func text(approximateTokens: Int) -> String {
        var text = ""
        while TokenEstimate.approximate(text) < approximateTokens {
            text += "The quick brown fox jumps over the lazy dog. "
        }
        return text
    }

    /// The `.talos` files a fresh project gets, so a growing shipped default
    /// moves this number rather than leaving a hand-written stand-in behind.
    private static func shippedLibrary() throws -> (guideline: GuidelineDocument, safeguards: SafeguardsDocument) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git", isDirectory: true), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try ProjectLibraryScaffolder.scaffold(projectRoot: root)
        let talos = root.appendingPathComponent(".talos", isDirectory: true)
        let guidelineFile = talos.appendingPathComponent("guidelines/automator.md")
        let guideline = try GuidelineDocumentParser.parse(
            contents: String(contentsOf: guidelineFile, encoding: .utf8),
            subFunction: .automator,
            file: guidelineFile.path
        )
        let safeguards = try SafeguardsDocument(
            rawText: String(contentsOf: talos.appendingPathComponent("safeguards.md"), encoding: .utf8)
        )
        return (guideline, safeguards)
    }

    @Test("A representative session stays under 5% of the agent's session tokens")
    func representativeSessionStaysUnderBudget() throws {
        let library = try Self.shippedLibrary()
        let input = ContextAssemblyInput(
            intent: makeTestIntent(content: "Fix the crash in the widget renderer.", requestingSubFunction: .automator),
            guideline: library.guideline,
            safeguards: library.safeguards,
            connectors: ConnectorsManifest(connectors: [
                ConnectorDeclaration(name: "repo", kind: .repo, target: "https://example.com/repo", reachedVia: .cli)
            ])
        )
        let assembler = makeTestAssembler(
            board: FakeContextSource(.available(Self.text(approximateTokens: Self.boardTokens))),
            memories: FakeContextSource(.available(Self.text(approximateTokens: Self.memoriesTokens)))
        )
        guard case let .assembled(assembled) = assembler.assemble(input) else {
            Issue.record("Expected assembly to succeed")
            return
        }

        // A budget measured over a session that injected almost nothing proves
        // nothing, so every source the guideline asks for must be in the numerator.
        let expected = Set([ContextPartKind.guideline, .safeguards, .connectors]
            + library.guideline.context.compactMap(ContextPartKind.init(rawValue:)))
        #expect(Set(assembled.injectedTokens.bySource.keys) == expected)

        let overhead = try #require(SessionOverhead(
            injected: assembled.injectedTokens,
            report: .measured(Self.reportedSession, model: "test-model")
        ))

        #expect(overhead.exceedsBudget == false)
        #expect(overhead.ratio < 0.05)
    }
}
