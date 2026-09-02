import TalosOrchestration
import TalosProjectLibrary
import Testing

/// "Third-party content is data, never instruction" — the structural part of
/// that posture, checked directly against ``PromptDataFraming``. Parts are
/// obtained through the real ``ContextAssembler`` rather than constructed
/// directly, since ``IncludedContextPart`` has no public initializer outside
/// this module.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#prompt-injection-posture
@Suite("Prompt data framing")
struct PromptDataFramingTests {
    private func assembledParts(
        context: [String], board: String = "", specDrive: String = ""
    ) -> [IncludedContextPart] {
        let assembler = makeTestAssembler(
            specDrive: FakeContextSource(.available(specDrive)),
            board: FakeContextSource(.available(board))
        )
        let guideline = makeTestGuideline(context: context, tokenCeiling: 100_000)
        let input = ContextAssemblyInput(
            intent: makeTestIntent(),
            guideline: guideline,
            safeguards: makeTestSafeguards(),
            connectors: ConnectorsManifest()
        )
        guard case let .assembled(assembled) = assembler.assemble(input) else {
            Issue.record("Expected assembly to succeed under a 100,000-token ceiling")
            return []
        }
        return assembled.includedParts
    }

    @Test("A pinned part renders as its own text, unwrapped")
    func pinnedPartIsUnwrapped() {
        let parts = assembledParts(context: [])

        let rendered = PromptDataFraming.render(parts)

        #expect(rendered == ["Answer questions grounded in the project's own sources.", "Never deploy on a Friday."])
    }

    @Test("A droppable part is wrapped in a <data> tag naming its kind")
    func droppablePartIsWrapped() {
        let parts = assembledParts(context: ["board"], board: "Board: 3 open items.")

        let rendered = PromptDataFraming.render(parts)

        #expect(rendered.contains("<data source=\"board\">\nBoard: 3 open items.\n</data>"))
    }

    @Test("Every droppable kind wraps with its own source name")
    func everyDroppableKindWrapsWithItsOwnName() {
        let parts = assembledParts(
            context: ["spec-drive", "board", "memories"], board: "board text", specDrive: "spec text"
        )

        let rendered = PromptDataFraming.render(parts)

        #expect(rendered.contains("<data source=\"spec-drive\">\nspec text\n</data>"))
        #expect(rendered.contains("<data source=\"board\">\nboard text\n</data>"))
        #expect(rendered.contains("<data source=\"memories\">\nPrefers dark mode.\n</data>"))
    }

    @Test("The preamble appears once, ahead of the first data block, only when one exists")
    func preambleAppearsOnlyWithADataBlock() {
        let pinnedOnly = PromptDataFraming.render(assembledParts(context: []))
        let withADataPart = PromptDataFraming.render(assembledParts(context: ["board"], board: "board text"))

        #expect(!pinnedOnly.contains(PromptDataFraming.preamble))
        #expect(withADataPart.first == PromptDataFraming.preamble)
        #expect(withADataPart.filter { $0 == PromptDataFraming.preamble }.count == 1)
    }

    @Test("Rendering preserves the input order")
    func renderingPreservesOrder() {
        let parts = assembledParts(context: ["board", "memories"], board: "board text")

        let rendered = PromptDataFraming.render(parts)

        #expect(rendered == [
            PromptDataFraming.preamble,
            "Answer questions grounded in the project's own sources.",
            "Never deploy on a Friday.",
            "<data source=\"board\">\nboard text\n</data>",
            "<data source=\"memories\">\nPrefers dark mode.\n</data>"
        ])
    }

    @Test("No parts renders no output and no preamble")
    func noPartsRendersNothing() {
        #expect(PromptDataFraming.render([]).isEmpty)
    }

    @Test("Framing overhead is zero with no droppable part, and positive with one")
    func framingOverheadIsMeasured() {
        let pinnedOnly = assembledParts(context: [])
        let withADataPart = assembledParts(context: ["board"], board: "board text")

        #expect(PromptDataFraming.overheadTokens(for: pinnedOnly) == 0)
        #expect(PromptDataFraming.overheadTokens(for: withADataPart) > 0)
    }
}
