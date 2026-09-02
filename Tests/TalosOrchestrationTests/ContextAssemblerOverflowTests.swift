@testable import TalosOrchestration
import TalosProjectLibrary
import Testing

/// Verifies overflow handling — whole-part drops, pinned parts never
/// dropped, the declared drop order, and a pinned-parts overflow failing
/// rather than being denied — per
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#when-assembled-context-exceeds-the-ceiling.
@Suite("Context assembler overflow")
struct ContextAssemblerOverflowTests {
    @Test("Dropping removes a whole part, never a fraction of it")
    func droppingNeverTruncates() {
        let memoriesText = "Memory fragment long enough to be dropped under a tight ceiling."
        let memories = FakeContextSource(.available(memoriesText))
        let fullSize = TokenEstimate.approximate(memoriesText)
        let pinnedTotal = TokenEstimate.approximate("G") + TokenEstimate.approximate("S")
        let ceiling = pinnedTotal // no room for any droppable part

        let input = ContextAssemblyInput(
            intent: makeTestIntent(),
            guideline: makeTestGuideline(context: ["memories"], tokenCeiling: ceiling, rawText: "G"),
            safeguards: makeTestSafeguards(rawText: "S"),
            connectors: ConnectorsManifest()
        )

        guard case let .assembled(assembled) = makeTestAssembler(memories: memories).assemble(input) else {
            Issue.record("Expected assembly to succeed with pinned parts alone at the ceiling")
            return
        }

        let expectedReason = "dropped to satisfy the assistant guideline's \(ceiling)-token ceiling"
        #expect(assembled.droppedParts == [
            DroppedContextPart(kind: .memories, estimatedTokens: fullSize, reason: expectedReason)
        ])
        #expect(!assembled.includedParts.contains { $0.kind == .memories })
    }

    @Test("The ceiling bounds the framed prompt, not only the raw content the framing wraps")
    func ceilingBoundsTheFramedPromptNotOnlyTheRawContent() {
        // "x" costs 1 raw token — small enough that a ceiling gating on raw
        // content alone would keep it — but framing a single droppable part
        // adds the preamble and a <data> tag, which does not fit in a
        // ceiling this tight. The dropping loop must gate on the framed
        // total, since that is what ``SafeguardsApproved/prompt`` actually
        // sends.
        // https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#when-assembled-context-exceeds-the-ceiling
        let memoriesText = "x"
        let memories = FakeContextSource(.available(memoriesText))
        let pinnedTotal = TokenEstimate.approximate("G") + TokenEstimate.approximate("S")
        let ceiling = pinnedTotal + TokenEstimate.approximate(memoriesText)

        let input = ContextAssemblyInput(
            intent: makeTestIntent(),
            guideline: makeTestGuideline(context: ["memories"], tokenCeiling: ceiling, rawText: "G"),
            safeguards: makeTestSafeguards(rawText: "S"),
            connectors: ConnectorsManifest()
        )

        guard case let .assembled(assembled) = makeTestAssembler(memories: memories).assemble(input) else {
            Issue.record("Expected assembly to succeed with pinned parts alone under the ceiling")
            return
        }

        #expect(assembled.droppedParts.map(\.kind) == [.memories])
        let framedTokens = TokenEstimate.approximate(
            PromptDataFraming.render(assembled.includedParts).joined(separator: "\n\n")
        )
        #expect(framedTokens <= ceiling)
    }

    @Test("The guideline and Safeguards are never dropped, even when every droppable part is")
    func pinnedPartsAreNeverDropped() {
        let ceiling = TokenEstimate.approximate("G") + TokenEstimate.approximate("S")
        let input = ContextAssemblyInput(
            intent: makeTestIntent(),
            guideline: makeTestGuideline(
                context: ["spec-drive", "connectors", "board", "memories"],
                tokenCeiling: ceiling,
                rawText: "G"
            ),
            safeguards: makeTestSafeguards(rawText: "S"),
            connectors: ConnectorsManifest(connectors: [
                ConnectorDeclaration(name: "repo", kind: .repo, target: "https://example.com", reachedVia: .cli)
            ])
        )

        guard case let .assembled(assembled) = makeTestAssembler().assemble(input) else {
            Issue.record("Expected assembly to succeed")
            return
        }

        #expect(Set(assembled.includedParts.map(\.kind)) == [.guideline, .safeguards])
        #expect(assembled.assembledTokens <= ceiling)
    }

    @Test("Parts drop in the declared order — memories, then board, before connectors or spec drive")
    func dropsInTheDeclaredOrder() {
        let memoriesText = "Memory fragment content for testing purposes that is somewhat long."
        let boardText = "Board fragment content for testing purposes that is somewhat long too."
        let specDriveText = "Spec drive fragment content for testing, also somewhat long."
        let connectorsManifest = ConnectorsManifest() // renders the fixed "no connectors declared" message

        let connectorsText = ConnectorsContextRendering.render(connectorsManifest)
        let connectorsTokens = TokenEstimate.approximate(connectorsText)
        let specDriveTokens = TokenEstimate.approximate(specDriveText)
        let boardTokens = TokenEstimate.approximate(boardText)
        let pinnedParts = [
            IncludedContextPart(kind: .guideline, text: "G", estimatedTokens: TokenEstimate.approximate("G")),
            IncludedContextPart(kind: .safeguards, text: "S", estimatedTokens: TokenEstimate.approximate("S"))
        ]
        let pinnedTotal = pinnedParts.reduce(0) { $0 + $1.estimatedTokens }
        let connectorsPart = IncludedContextPart(
            kind: .connectors, text: connectorsText, estimatedTokens: connectorsTokens
        )
        let specDrivePart = IncludedContextPart(kind: .specDrive, text: specDriveText, estimatedTokens: specDriveTokens)
        let boardPart = IncludedContextPart(kind: .board, text: boardText, estimatedTokens: boardTokens)

        // Chosen so dropping memories alone is not enough (board must drop
        // too), but dropping both memories and board is exactly enough —
        // where "enough" is measured against the *framed* total the agent
        // actually receives, not against the raw content alone.
        // https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#when-assembled-context-exceeds-the-ceiling
        let keptOverhead = PromptDataFraming.overheadTokens(for: pinnedParts + [connectorsPart, specDrivePart])
        let ceiling = pinnedTotal + connectorsTokens + specDriveTokens + keptOverhead
        let withBoardOverhead = PromptDataFraming.overheadTokens(
            for: pinnedParts + [boardPart, connectorsPart, specDrivePart]
        )
        #expect(pinnedTotal + boardTokens + connectorsTokens + specDriveTokens + withBoardOverhead > ceiling)

        let input = ContextAssemblyInput(
            intent: makeTestIntent(),
            guideline: makeTestGuideline(
                context: ["spec-drive", "connectors", "board", "memories"],
                tokenCeiling: ceiling,
                rawText: "G"
            ),
            safeguards: makeTestSafeguards(rawText: "S"),
            connectors: connectorsManifest
        )
        let memories = FakeContextSource(.available(memoriesText))
        let board = FakeContextSource(.available(boardText))
        let specDrive = FakeContextSource(.available(specDriveText))

        guard case let .assembled(assembled) = makeTestAssembler(
            specDrive: specDrive,
            board: board,
            memories: memories
        ).assemble(input) else {
            Issue.record("Expected assembly to succeed")
            return
        }

        #expect(assembled.droppedParts.map(\.kind) == [.memories, .board])
        #expect(Set(assembled.includedParts.map(\.kind)) == [.guideline, .safeguards, .connectors, .specDrive])
        #expect(assembled.assembledTokens <= ceiling)
    }

    @Test("Pinned parts alone exceeding the ceiling fails, naming the ceiling, each pinned cost, and its file")
    func pinnedOverflowFails() {
        let guidelineText = "A guideline long enough that its own text exceeds a tiny ceiling."
        let safeguardsText = "Safeguards text that is also long enough on its own."
        let guidelineTokens = TokenEstimate.approximate(guidelineText)
        let safeguardsTokens = TokenEstimate.approximate(safeguardsText)
        let ceiling = guidelineTokens + safeguardsTokens - 1

        let input = ContextAssemblyInput(
            intent: makeTestIntent(),
            guideline: makeTestGuideline(subFunction: .automator, tokenCeiling: ceiling, rawText: guidelineText),
            safeguards: makeTestSafeguards(rawText: safeguardsText),
            connectors: ConnectorsManifest()
        )

        guard case let .failed(failure) = makeTestAssembler().assemble(input) else {
            Issue.record("Expected assembly to fail when the pinned parts alone exceed the ceiling")
            return
        }

        #expect(failure.ceiling == ceiling)
        #expect(failure.pinnedCosts == [
            PinnedPartCost(kind: .guideline, estimatedTokens: guidelineTokens, file: ".talos/guidelines/automator.md"),
            PinnedPartCost(kind: .safeguards, estimatedTokens: safeguardsTokens, file: ".talos/safeguards.md")
        ])
    }
}
