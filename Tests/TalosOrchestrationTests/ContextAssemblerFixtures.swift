import TalosOrchestration
import TalosProjectLibrary

/// Shared fixture builders for the `ContextAssembler*Tests` suites, kept as
/// free functions rather than duplicated per suite.
func makeTestGuideline(
    subFunction: SubFunction = .assistant,
    context: [String] = [],
    tokenCeiling: Int,
    rawText: String = "Answer questions grounded in the project's own sources."
) -> GuidelineDocument {
    GuidelineDocument(
        subFunction: subFunction,
        purpose: "Test purpose.",
        context: context,
        tokenCeiling: tokenCeiling,
        outputExpectations: "Test output expectations.",
        rawText: rawText
    )
}

func makeTestSafeguards(rawText: String = "Never deploy on a Friday.") -> SafeguardsDocument {
    SafeguardsDocument(rawText: rawText)
}

func makeTestIntent(
    content: String = "Add a dark mode toggle.",
    project: ProjectIdentifier = .generate(),
    requestingSubFunction: SubFunction = .assistant
) -> Intent {
    Intent(
        content: content,
        source: .userText,
        project: project,
        requestingSubFunction: requestingSubFunction
    )
}

func makeTestAssembler(
    specDrive: FakeContextSource = FakeContextSource(.available("Spec drive excerpt.")),
    board: FakeContextSource = FakeContextSource(.available("Board: 3 open items.")),
    memories: FakeContextSource = FakeContextSource(.available("Prefers dark mode."))
) -> ContextAssembler {
    ContextAssembler(specDriveSource: specDrive, boardSource: board, memoriesSource: memories)
}
