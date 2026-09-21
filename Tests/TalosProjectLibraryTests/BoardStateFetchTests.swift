import Foundation
@testable import TalosProjectLibrary
import Testing

/// Verifies the board is read through the agent's own tools into `.talos/local/`
/// per [decision 93](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions),
/// and that the request fixes a canonical shape so no provider-specific field
/// reaches Talos.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#board
@Suite("Board state fetch request")
struct BoardStateFetchTests {
    private static func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private static func board(_ provider: BoardProviderKind = .githubProjects) -> BoardManifest {
        BoardManifest(provider: provider, columns: [BoardColumnMapping(column: "Todo", state: .ready)])
    }

    @Test("Fetched items land under .talos/local/, which is never committed")
    func destinationLivesUnderLocal() {
        let root = Self.root()
        let request = BoardStateFetch.fetchRequest(for: Self.board(), projectRoot: root)

        #expect(request.destination.path.hasPrefix(root.appendingPathComponent(".talos/local/board").path))
    }

    @Test("The same project resolves to the same destination every refresh")
    func destinationIsStable() {
        let root = Self.root()
        let first = BoardStateFetch.fetchRequest(for: Self.board(), projectRoot: root)
        let again = BoardStateFetch.fetchRequest(for: Self.board(.jira), projectRoot: root)

        #expect(first.destination == again.destination)
    }

    @Test("The instruction names the provider, the destination, and the canonical id/title/column shape")
    func instructionNamesProviderDestinationAndShape() {
        let root = Self.root()
        let request = BoardStateFetch.fetchRequest(for: Self.board(.githubProjects), projectRoot: root)

        #expect(request.instruction.contains("github-projects"))
        #expect(request.instruction.contains(request.destination.path))
        #expect(request.instruction.contains("\"id\""))
        #expect(request.instruction.contains("\"title\""))
        #expect(request.instruction.contains("\"column\""))
        // The column is kept as the provider's own name — the agent maps its
        // provider onto the canonical shape, so no provider field reaches Talos.
        #expect(request.instruction.contains("unchanged"))
        // Reading assembles context; the run never writes to the board itself.
        #expect(request.instruction.contains("change nothing on the board"))
        // The items are never asked for as the agent's answer — Talos reads the file.
        #expect(request.instruction.contains("Do not reproduce the items in your reply"))
    }
}
