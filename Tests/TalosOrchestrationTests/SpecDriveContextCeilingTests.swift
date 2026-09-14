@testable import TalosOrchestration
import TalosProjectLibrary
import Testing

/// Asserts assembled Spec Drive context stays inside the requesting
/// guideline's declared token ceiling, however large the index behind it is —
/// the budget that makes the < 5% token overhead measurable rather than
/// asserted.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#when-assembled-context-exceeds-the-ceiling
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable
@Suite("Spec Drive context ceiling")
struct SpecDriveContextCeilingTests {
    private static let question = "How long are session transcripts retained?"

    private static let specDrive = SpecDrive.locations([
        SpecDriveLocation(provider: .githubWiki, url: "https://example/wiki", syncRule: .readOnly)
    ])

    /// An index far larger than any ceiling would admit, every section a
    /// lexical match for the question so the cap under test is the budget and
    /// never a shortage of candidates.
    private static func largeIndex(count: Int = 300) -> [SpecSection] {
        (0 ..< count).map { ordinal in
            SpecSection(
                pageTitle: "Sessions",
                headingPath: ["Sessions", "Retention window \(ordinal)"],
                anchor: GitHubHeadingSlug.slug(for: "Retention window \(ordinal)"),
                body: "Session transcripts are retained for \(ordinal) days under rule \(ordinal).",
                isDraft: false,
                ordinal: ordinal
            )
        }
    }

    private static func assemble(ceiling: Int) -> ContextAssemblyResult {
        let assembler = ContextAssembler(
            specDriveSource: SpecDriveRetrieval(specDrive: specDrive, sections: largeIndex()),
            boardSource: FakeContextSource(.unavailable(reason: "No board.")),
            memoriesSource: FakeContextSource(.unavailable(reason: "No memories."))
        )
        return assembler.assemble(ContextAssemblyInput(
            intent: makeTestIntent(content: question),
            guideline: makeTestGuideline(context: ["spec-drive"], tokenCeiling: ceiling),
            safeguards: makeTestSafeguards(),
            connectors: ConnectorsManifest()
        ))
    }

    /// The tokens that actually reach the agent — the assembled content plus
    /// the framing wrapped around it, which is what the ceiling bounds.
    private static func framedTokens(_ context: AssembledContext) -> Int {
        context.assembledTokens + PromptDataFraming.overheadTokens(for: context.includedParts)
    }

    private static let pinnedTokens = TokenEstimate.approximate(makeTestGuideline(tokenCeiling: 1).rawText)
        + TokenEstimate.approximate(makeTestSafeguards().rawText)

    @Test("Retrieval over a large index selects within its token budget rather than everything")
    func retrievalStaysWithinItsBudget() {
        let index = Self.largeIndex()
        let selected = SpecLexicalRanking.select(
            sections: index,
            query: Self.question,
            tokenBudget: SpecDriveRetrieval.defaultTokenBudget
        )

        let selectedTokens = selected.reduce(0) { $0 + TokenEstimate.approximate($1.body) }
        #expect(selectedTokens <= SpecDriveRetrieval.defaultTokenBudget)
        #expect(selected.count < index.count)
        #expect(!selected.isEmpty)
    }

    @Test("Assembled spec context fits the guideline's ceiling")
    func assembledSpecContextFitsTheCeiling() {
        let ceiling = 4000
        guard case let .assembled(context) = Self.assemble(ceiling: ceiling) else {
            Issue.record("Expected assembly to succeed under a \(ceiling)-token ceiling")
            return
        }

        #expect(context.includedParts.contains { $0.kind == .specDrive })
        #expect(Self.framedTokens(context) <= ceiling)
    }

    @Test("A spec context too large for the ceiling is dropped whole, never truncated")
    func oversizedSpecContextIsDroppedWhole() {
        // One token above the pinned parts: enough to assemble, never enough
        // for any spec context at all.
        let ceiling = Self.pinnedTokens + 1
        guard case let .assembled(context) = Self.assemble(ceiling: ceiling) else {
            Issue.record("Expected assembly to succeed with the pinned parts inside a \(ceiling)-token ceiling")
            return
        }

        #expect(!context.includedParts.contains { $0.kind == .specDrive })
        let dropped = context.droppedParts.first { $0.kind == .specDrive }
        #expect(dropped != nil)
        #expect(dropped?.estimatedTokens ?? 0 > 0)
        #expect(Self.framedTokens(context) <= ceiling)
    }
}
