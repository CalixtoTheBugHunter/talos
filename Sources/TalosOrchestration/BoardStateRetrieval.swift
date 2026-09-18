import TalosProjectLibrary

/// The real ``BoardStateContextSource`` for a project: it renders the board
/// items already read for this session into context, mapping each provider
/// column onto one of the six internal states through the project's
/// ``BoardManifest``. The connected agent reads the board through its own
/// MCP/CLI and the items land out of band — the same shape as
/// [the Spec Drive index](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#how-specs-are-retrieved) —
/// so this synchronous `fetch` never touches disk or the network, per
/// [decision 93](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions).
///
/// A labeled ``ContextFragment/unavailable(reason:)`` is returned whenever
/// there is nothing to inject — no board configured, or none read yet — so the
/// absence is visible where the output is read rather than silently shaping it.
public struct BoardStateRetrieval: BoardStateContextSource {
    private let board: BoardManifest?
    private let items: [BoardItem]

    public init(board: BoardManifest?, items: [BoardItem] = []) {
        self.board = board
        self.items = items
    }

    public func fetch(for _: Intent) -> ContextFragment {
        guard let board else {
            return .unavailable(reason: "This project has no board configured.")
        }
        guard !items.isEmpty else {
            return .unavailable(reason: "No board items have been read yet.")
        }
        return .available(items.map { render($0, board: board) }.joined(separator: "\n"))
    }

    /// The render is provider-agnostic: it reads only the column-to-state
    /// mapping, so every provider's board renders identically. An item in an
    /// unmapped column is a named missing part, never defaulted to `backlog`
    /// — decision 58.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#the-canonical-internal-states
    private func render(_ item: BoardItem, board: BoardManifest) -> String {
        let state: String = switch board.state(forColumn: item.column) {
        case let .mapped(internalState):
            internalState.rawValue
        case .unmapped:
            "unmapped column '\(item.column)'"
        }
        return "- \(item.title) (\(item.id)) — \(state)"
    }
}
