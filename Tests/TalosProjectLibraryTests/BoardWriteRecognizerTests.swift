import TalosProjectLibrary
import Testing

/// The recognizer reads a board move's item and target column from the
/// structured arguments the adapter preserved — the board-provider-aware half
/// of decision 94 — and recognizes nothing it should not.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions
@Suite("Board write recognizer")
struct BoardWriteRecognizerTests {
    private let recognizer = BoardWriteRecognizer(provider: .githubProjects)

    @Test("A github-projects item move yields its item and target column")
    func recognizesAMove() {
        let write = recognizer.boardWrite(
            toolName: "update_project_item_field",
            arguments: ["item_id": "PVTI_42", "status": "In review"]
        )
        #expect(write == BoardWriteRecognizer.BoardWrite(itemID: "PVTI_42", targetColumn: "In review"))
    }

    @Test("A call with an item but no target column is not a recognized board write")
    func requiresATargetColumn() {
        #expect(recognizer.boardWrite(toolName: "get_item", arguments: ["item_id": "PVTI_42"]) == nil)
    }

    @Test("An ordinary write carrying neither key is not a board write")
    func ignoresANonBoardWrite() {
        #expect(recognizer.boardWrite(toolName: "file.write", arguments: ["path": "Sources/App.swift"]) == nil)
    }

    @Test("An empty item id or column is not a recognized board write")
    func rejectsEmptyValues() {
        #expect(recognizer.boardWrite(toolName: "update", arguments: ["item_id": "", "status": "Done"]) == nil)
    }

    @Test("Jira board writes are not recognized yet, so they are gated as normal and not conflict-checked")
    func jiraIsNotRecognizedYet() {
        let jira = BoardWriteRecognizer(provider: .jira)
        #expect(jira.boardWrite(toolName: "transition_issue", arguments: ["item_id": "T-1", "status": "Done"]) == nil)
    }
}
