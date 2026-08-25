@testable import TalosProjectLibrary
import Testing

/// Verifies `.talos/guidelines/*.md` parsing against ``GuidelineDocument``:
/// a valid file, the inert-marking `SubFunction.isActiveAtMVP` exposes, and
/// the hand-edit round-trip. Validation-failure cases are in
/// ``GuidelineDocumentValidationTests``.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#editable-talos-guidelines
@Suite("Guideline document")
struct GuidelineDocumentTests {
    private static let validContents = """
    ---
    # Assistant guideline — active at MVP.
    purpose: >-
      Answer questions about this project accurately.
    context:
      - spec-drive
      - memories
    tokenCeiling: 4000
    outputExpectations: >-
      Concise answers with every claim traceable to a cited source.
    ---

    Notes are yours to add below this line.
    """

    // MARK: - A valid file parses into the typed model

    @Test("A valid file parses all four declared elements")
    func parsesAValidFile() throws {
        let document = try GuidelineDocumentParser.parse(
            contents: Self.validContents, subFunction: .assistant, file: "assistant.md"
        )

        #expect(document.subFunction == .assistant)
        #expect(document.purpose == "Answer questions about this project accurately.")
        #expect(document.context == ["spec-drive", "memories"])
        #expect(document.tokenCeiling == 4000)
        #expect(document.outputExpectations == "Concise answers with every claim traceable to a cited source.")
        #expect(document.rawText == Self.validContents)
    }

    @Test("An empty context sequence parses into zero entries rather than an error")
    func emptyContextSequenceParses() throws {
        let contents = """
        ---
        purpose: >-
          Present but inert.
        context: []
        tokenCeiling: 2000
        outputExpectations: >-
          Present but inert.
        ---
        """
        let document = try GuidelineDocumentParser.parse(contents: contents, subFunction: .advisor, file: "advisor.md")
        #expect(document.context.isEmpty)
    }

    @Test("A context entry naming anything is accepted — no fixed vocabulary is enforced")
    func contextIsFreeform() throws {
        let contents = """
        ---
        purpose: >-
          Purpose text.
        context:
          - some-future-context-part
        tokenCeiling: 1000
        outputExpectations: >-
          Output text.
        ---
        """
        let document = try GuidelineDocumentParser.parse(
            contents: contents, subFunction: .automator, file: "automator.md"
        )
        #expect(document.context == ["some-future-context-part"])
    }

    // MARK: - isActiveAtMVP: the fact a context assembler checks

    @Test("Assistant and Automator are active at MVP")
    func assistantAndAutomatorAreActive() {
        #expect(SubFunction.assistant.isActiveAtMVP)
        #expect(SubFunction.automator.isActiveAtMVP)
    }

    @Test("Advisor and Self-improver are marked inert")
    func advisorAndSelfImproverAreInert() {
        #expect(!SubFunction.advisor.isActiveAtMVP)
        #expect(!SubFunction.selfImprover.isActiveAtMVP)
    }

    @Test("guidelineFileName matches the scaffolded filename exactly")
    func guidelineFileNameMatchesScaffoldedFilename() {
        #expect(SubFunction.assistant.guidelineFileName == "assistant.md")
        #expect(SubFunction.selfImprover.guidelineFileName == "self-improver.md")
    }

    // MARK: - AC5: a hand-edited guideline round-trips without loss

    @Test("A hand-edited guideline, with reordered fields and added notes, round-trips without loss")
    func handEditedGuidelineRoundTripsWithoutLoss() throws {
        let handEdited = """
        ---
        # A user's own header, in their own words.
        tokenCeiling: 6500
        outputExpectations: >-
          Cite the exact file and line for every claim.
        purpose: >-
          Answer only from the Spec Drive; never guess.
        context:
          - spec-drive
        ---

        ## My own notes

        This guideline was hand-edited on this project. Talos never rewrites
        this file, so these notes and the reordered fields above must survive
        exactly as written.
        """

        let document = try GuidelineDocumentParser.parse(
            contents: handEdited, subFunction: .assistant, file: "assistant.md"
        )

        #expect(document.tokenCeiling == 6500)
        #expect(document.outputExpectations == "Cite the exact file and line for every claim.")
        #expect(document.purpose == "Answer only from the Spec Drive; never guess.")
        #expect(document.context == ["spec-drive"])
        #expect(document.rawText == handEdited)
    }
}
