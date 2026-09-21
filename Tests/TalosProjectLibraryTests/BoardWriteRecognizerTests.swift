import TalosProjectLibrary
import Testing

/// The recognizer reads a board move's item and target column from the
/// structured arguments the adapter preserved — the board-provider-aware half
/// of decision 94 — matching the real `projects_write` tool's `method`,
/// `item_id`/`node_id`, and nested `updated_field.value`, and recognizing
/// nothing it should not.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions
@Suite("Board write recognizer")
struct BoardWriteRecognizerTests {
    private let recognizer = BoardWriteRecognizer(provider: .githubProjects)

    @Test("A projects_write single-item update yields its item and target column")
    func recognizesAMove() {
        let write = recognizer.boardWrite(
            toolName: "projects_write",
            arguments: ["method": "update_project_item", "item_id": "PVTI_42", "updated_field.value": "In review"]
        )
        #expect(write == BoardWriteRecognizer.BoardWrite(itemID: "PVTI_42", targetColumn: "In review"))
    }

    @Test("A move identifying the item by node_id is recognized the same way")
    func recognizesANodeIDMove() {
        let write = recognizer.boardWrite(
            toolName: "projects_write",
            arguments: ["method": "update_project_item", "node_id": "PVTI_42", "updated_field.value": "Done"]
        )
        #expect(write == BoardWriteRecognizer.BoardWrite(itemID: "PVTI_42", targetColumn: "Done"))
    }

    @Test("A create is not a conflict-checkable write — it has no prior state to diverge from")
    func ignoresACreate() {
        #expect(recognizer.boardWrite(
            toolName: "projects_write",
            arguments: ["method": "add_project_item", "item_id": "PVTI_42", "updated_field.value": "Done"]
        ) == nil)
    }

    @Test("A call with an item but no target column is not a recognized board write")
    func requiresATargetColumn() {
        #expect(recognizer.boardWrite(
            toolName: "projects_get",
            arguments: ["method": "get_project_item", "item_id": "PVTI_42"]
        ) == nil)
    }

    @Test("An ordinary write carrying neither key is not a board write")
    func ignoresANonBoardWrite() {
        #expect(recognizer.boardWrite(toolName: "file.write", arguments: ["path": "Sources/App.swift"]) == nil)
    }

    @Test("An empty item id or column is not a recognized board write")
    func rejectsEmptyValues() {
        #expect(recognizer.boardWrite(
            toolName: "projects_write",
            arguments: ["method": "update_project_item", "item_id": "", "updated_field.value": "Done"]
        ) == nil)
    }

    @Test("Jira board writes are not recognized yet, so they are gated as normal and not conflict-checked")
    func jiraIsNotRecognizedYet() {
        let jira = BoardWriteRecognizer(provider: .jira)
        #expect(jira.boardWrite(
            toolName: "transition_issue",
            arguments: ["method": "update_project_item", "item_id": "T-1", "updated_field.value": "Done"]
        ) == nil)
    }
}
