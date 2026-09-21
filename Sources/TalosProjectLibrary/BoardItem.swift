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
    /// Who last changed the item, when the read supplied it — shown in the
    /// conflict prompt so a divergence names its author. `nil` when the
    /// provider or the read carried none.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#when-a-human-and-talos-move-the-same-item
    public let updatedBy: String?
    /// When the item last changed, as the provider stated it. `nil` when
    /// absent — the prompt reads it as unknown rather than inventing one.
    public let updatedAt: String?

    public init(id: String, title: String, column: String, updatedBy: String? = nil, updatedAt: String? = nil) {
        self.id = id
        self.title = title
        self.column = column
        self.updatedBy = updatedBy
        self.updatedAt = updatedAt
    }
}
