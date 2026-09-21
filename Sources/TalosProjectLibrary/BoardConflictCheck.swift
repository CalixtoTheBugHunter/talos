import Foundation

/// Compares the state Talos believes it is changing *from* against what is
/// really on the board now, for one item — the detect step of
/// [decision 42](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions)'s
/// detect-and-ask. A pure function of the two reads and the manifest: no I/O,
/// no board client. The caller supplies "expected" from assembled context and
/// "actual" from the out-of-band read
/// ([decision 94](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions)).
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#when-a-human-and-talos-move-the-same-item
public struct BoardConflictCheck: Sendable {
    /// What the comparison found. A conflict is nameable only when Talos holds
    /// two known, differing states for the item — the pair the SPEC calls what
    /// "makes a conflict nameable"; anything less proceeds rather than
    /// inventing a divergence from missing data.
    public enum Result: Equatable, Sendable {
        case agree
        case diverged(Divergence)
    }

    /// A named divergence: the item as it really is now, and the two states
    /// that differ. `item` carries the title and, where the read supplied it,
    /// who changed it and when — what the conflict prompt shows.
    public struct Divergence: Equatable, Sendable {
        public let item: BoardItem
        public let expected: BoardState
        public let actual: BoardState

        public init(item: BoardItem, expected: BoardState, actual: BoardState) {
            self.item = item
            self.expected = expected
            self.actual = actual
        }
    }

    private let manifest: BoardManifest

    public init(manifest: BoardManifest) {
        self.manifest = manifest
    }

    /// Resolves the item's expected and actual internal states and reports a
    /// divergence only when both resolve and differ. An item missing from
    /// either read, or in a column the manifest leaves unmapped, yields
    /// ``Result/agree``: without both values there is no conflict to name, and
    /// blocking the write on absent data would stop legitimate work.
    public func evaluate(itemID: String, expected: [BoardItem], actual: [BoardItem]) -> Result {
        guard let expectedState = state(ofItem: itemID, in: expected),
              let actualState = state(ofItem: itemID, in: actual)
        else {
            return .agree
        }
        guard expectedState != actualState else {
            return .agree
        }
        let item = actual.first { $0.id == itemID } ?? expected.first { $0.id == itemID }
        return .diverged(Divergence(item: item ?? BoardItem(id: itemID, title: itemID, column: ""),
                                    expected: expectedState,
                                    actual: actualState))
    }

    private func state(ofItem itemID: String, in items: [BoardItem]) -> BoardState? {
        guard let item = items.first(where: { $0.id == itemID }) else { return nil }
        guard case let .mapped(state) = manifest.state(forColumn: item.column) else { return nil }
        return state
    }
}
