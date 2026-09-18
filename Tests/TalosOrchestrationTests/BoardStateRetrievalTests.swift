import TalosOrchestration
import TalosProjectLibrary
import Testing

@Suite("BoardStateRetrieval renders board items into context by internal state")
struct BoardStateRetrievalTests {
    private let githubProjects = BoardManifest(
        provider: .githubProjects,
        columns: [
            BoardColumnMapping(column: "Todo", state: .ready),
            BoardColumnMapping(column: "In Progress", state: .inProgress),
            BoardColumnMapping(column: "Done", state: .done)
        ]
    )

    @Test("Maps each provider column to its internal state")
    func mapsColumnsToStates() {
        let retrieval = BoardStateRetrieval(board: githubProjects, items: [
            BoardItem(id: "1", title: "Wire the board", column: "In Progress"),
            BoardItem(id: "2", title: "Ship it", column: "Todo")
        ])
        guard case let .available(rendered) = retrieval.fetch(for: makeTestIntent()) else {
            Issue.record("expected available board context")
            return
        }
        #expect(rendered.contains("Wire the board (1) — in-progress"))
        #expect(rendered.contains("Ship it (2) — ready"))
    }

    @Test("An item in an unmapped column is labeled, never defaulted to backlog — decision 58")
    func unmappedColumnIsLabeledNotDefaulted() {
        let retrieval = BoardStateRetrieval(board: githubProjects, items: [
            BoardItem(id: "9", title: "Triage", column: "Icebox")
        ])
        guard case let .available(rendered) = retrieval.fetch(for: makeTestIntent()) else {
            Issue.record("expected available board context")
            return
        }
        #expect(rendered.contains("unmapped column 'Icebox'"))
        #expect(!rendered.contains("backlog"))
    }

    @Test("No board configured is a labeled absence")
    func noBoardConfigured() {
        let retrieval = BoardStateRetrieval(board: nil)
        #expect(
            retrieval.fetch(for: makeTestIntent())
                == .unavailable(reason: "This project has no board configured.")
        )
    }

    @Test("A configured board with no items read yet is a labeled absence")
    func noItemsReadYet() {
        let retrieval = BoardStateRetrieval(board: githubProjects, items: [])
        #expect(
            retrieval.fetch(for: makeTestIntent())
                == .unavailable(reason: "No board items have been read yet.")
        )
    }

    @Test("The render is provider-agnostic — jira and github-projects render identically")
    func providerAgnosticRender() {
        let items = [BoardItem(id: "7", title: "Review PR", column: "Code Review")]
        let jira = BoardManifest(
            provider: .jira,
            columns: [BoardColumnMapping(column: "Code Review", state: .inReview)]
        )
        let ghp = BoardManifest(
            provider: .githubProjects,
            columns: [BoardColumnMapping(column: "Code Review", state: .inReview)]
        )
        #expect(
            BoardStateRetrieval(board: jira, items: items).fetch(for: makeTestIntent())
                == BoardStateRetrieval(board: ghp, items: items).fetch(for: makeTestIntent())
        )
    }
}
