/// One board item as the connected agent read it. The agent performs every
/// board read through its own MCP/CLI and Talos holds no board client, per
/// [decision 93](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions).
/// `column` is the provider's own column name; ``BoardManifest`` maps it onto
/// one of the six internal states — never the reverse.
public struct BoardItem: Equatable, Sendable {
    /// The provider's stable identifier for the item.
    public let id: String
    /// The item's human-readable title.
    public let title: String
    /// The provider's own column name, mapped through
    /// [`board.yaml`](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#board).
    public let column: String

    public init(id: String, title: String, column: String) {
        self.id = id
        self.title = title
        self.column = column
    }
}
