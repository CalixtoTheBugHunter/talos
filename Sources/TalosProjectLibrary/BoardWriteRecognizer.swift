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
/// Recognition keys off the argument *keys*, not a fixed tool name: a board
/// move is named by an item identifier and a target column together, a pair no
/// ordinary file or git write carries. A provider with no key set — Jira, at
/// MVP — is not recognized, so its writes are gated as normal and simply not
/// conflict-checked yet; adding it is a key set here, not a core change.
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

    /// The argument keys that name an item and a target column for a provider,
    /// or `nil` for a provider Talos does not recognize board writes for yet.
    private static func keys(for provider: BoardProviderKind) -> (itemID: [String], targetColumn: [String])? {
        switch provider {
        case .githubProjects:
            (
                itemID: ["item_id", "itemId", "item", "id"],
                targetColumn: ["status", "column", "state", "target_column", "value"]
            )
        case .jira:
            // Jira board-write recognition is a follow-up; its writes are gated
            // as normal and not conflict-checked until its key set lands.
            nil
        }
    }
}
