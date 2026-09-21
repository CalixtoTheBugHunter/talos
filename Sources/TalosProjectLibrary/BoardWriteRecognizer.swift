import Foundation

/// Recognizes a board move or field update among the agent's gated tool calls
/// and reads the item and target column it names, per the declared provider.
/// This is the board-provider-aware half of
/// [decision 94](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions):
/// it lets Talos conflict-check the agent's `board.item.move`/`update` without
/// holding a board client, working from the structured arguments the adapter
/// preserved on the held request rather than from the raw tool name a core
/// reader may not switch on.
///
/// Recognition matches the real provider tool's argument names, not the tool
/// name a core reader may not switch on. For `github-projects` that is the
/// consolidated `projects_write` tool, whose operation is chosen by a `method`
/// argument and whose new column value rides inside an `updated_field` object
/// the adapter surfaces as the dotted key `updated_field.value`. Only a
/// single-item update is a conflict-checkable move: a create has no prior state
/// to diverge from and a delete moves nothing. A provider with no key set —
/// Jira, at MVP — is not recognized, so its writes are gated as normal and
/// simply not conflict-checked yet; adding it is a key set here, not a core
/// change.
///
/// The names are taken from the `github/github-mcp-server` `projects_write`
/// tool rather than a live capture; a captured `projects_write` permission
/// request should pin them end to end.
public struct BoardWriteRecognizer: Sendable {
    /// A recognized board write: which item, and the provider column it moves
    /// the item to.
    public struct BoardWrite: Equatable, Sendable {
        public let itemID: String
        public let targetColumn: String

        public init(itemID: String, targetColumn: String) {
            self.itemID = itemID
            self.targetColumn = targetColumn
        }
    }

    private let provider: BoardProviderKind

    public init(provider: BoardProviderKind) {
        self.provider = provider
    }

    /// The board write a permission request names, or `nil` when it is not a
    /// board move/update for this provider — in which case no conflict check
    /// runs and the gate's decision stands unchanged.
    public func boardWrite(toolName _: String?, arguments: [String: String]) -> BoardWrite? {
        guard let keys = Self.keys(for: provider) else { return nil }
        // A consolidated projects tool selects its operation with `method`; only
        // a single-item update moves an item that already has a state to
        // diverge from. A declared method that is not that update is not a
        // conflict-checkable write. A tool that carries no method at all falls
        // through to the key match below.
        if let method = arguments[keys.method], !keys.updateMethods.contains(method) {
            return nil
        }
        guard let itemID = firstValue(in: arguments, forAnyKey: keys.itemID), !itemID.isEmpty else {
            return nil
        }
        guard let targetColumn = firstValue(in: arguments, forAnyKey: keys.targetColumn), !targetColumn.isEmpty else {
            return nil
        }
        return BoardWrite(itemID: itemID, targetColumn: targetColumn)
    }

    private func firstValue(in arguments: [String: String], forAnyKey candidates: [String]) -> String? {
        for key in candidates {
            if let value = arguments[key] {
                return value
            }
        }
        return nil
    }

    /// The argument keys that name the operation, the item, and the target
    /// column for a provider Talos recognizes board writes for.
    private struct ProviderKeys {
        let method: String
        let updateMethods: Set<String>
        let itemID: [String]
        let targetColumn: [String]
    }

    /// The keys for a provider, or `nil` for one Talos does not recognize board
    /// writes for yet.
    private static func keys(for provider: BoardProviderKind) -> ProviderKeys? {
        switch provider {
        case .githubProjects:
            ProviderKeys(
                method: "method",
                updateMethods: ["update_project_item"],
                itemID: ["item_id", "node_id"],
                targetColumn: ["updated_field.value"]
            )
        case .jira:
            // Jira board-write recognition is a follow-up; its writes are gated
            // as normal and not conflict-checked until its key set lands.
            nil
        }
    }
}
