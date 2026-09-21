import TalosProjectLibrary
import Testing

/// The comparison reports a divergence only when Talos holds two known,
/// differing internal states for the item — the pair that "makes a conflict
/// nameable" — and proceeds otherwise.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#when-a-human-and-talos-move-the-same-item
@Suite("Board conflict check")
struct BoardConflictCheckTests {
    private let manifest = BoardManifest(provider: .githubProjects, columns: [
        BoardColumnMapping(column: "Todo", state: .ready),
        BoardColumnMapping(column: "In Progress", state: .inProgress),
        BoardColumnMapping(column: "Done", state: .done)
    ])

    private func check() -> BoardConflictCheck {
        BoardConflictCheck(manifest: manifest)
    }

    @Test("Matching expected and actual states agree, so nobody is prompted")
    func agreesWhenStatesMatch() {
        let expected = [BoardItem(id: "1", title: "Ship it", column: "Todo")]
        let actual = [BoardItem(id: "1", title: "Ship it", column: "Todo")]
        #expect(check().evaluate(itemID: "1", expected: expected, actual: actual) == .agree)
    }

    @Test("A state a human changed since assembly is a named divergence carrying who, when, and the item's url")
    func divergesWhenStatesDiffer() {
        let expected = [BoardItem(id: "1", title: "Ship it", column: "Todo")]
        let actual = [BoardItem(
            id: "1", title: "Ship it", column: "Done",
            updatedBy: "ada", updatedAt: "2026-09-21", url: "https://example.com/item/1"
        )]
        let result = check().evaluate(itemID: "1", expected: expected, actual: actual)
        // The divergence carries the actual item whole — including the url the
        // conflict prompt's "Open the item" opens.
        #expect(result == .diverged(BoardConflictCheck.Divergence(
            item: BoardItem(
                id: "1", title: "Ship it", column: "Done",
                updatedBy: "ada", updatedAt: "2026-09-21", url: "https://example.com/item/1"
            ),
            expected: .ready,
            actual: .done
        )))
    }

    @Test("An item missing from the re-read has no nameable conflict, so the write proceeds")
    func agreesWhenItemAbsentFromActual() {
        let expected = [BoardItem(id: "1", title: "Ship it", column: "Todo")]
        #expect(check().evaluate(itemID: "1", expected: expected, actual: []) == .agree)
    }

    @Test("An item in an unmapped column has no resolvable state, so the write proceeds")
    func agreesWhenColumnUnmapped() {
        let expected = [BoardItem(id: "1", title: "Ship it", column: "Todo")]
        let actual = [BoardItem(id: "1", title: "Ship it", column: "Icebox")]
        #expect(check().evaluate(itemID: "1", expected: expected, actual: actual) == .agree)
    }
}
