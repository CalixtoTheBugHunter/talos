/// A ``SpecDriveContextSource``/``BoardStateContextSource``/``MemoriesContextSource``
/// conformance that reports every fetch as unavailable, naming the backlog
/// item that will back it. Each protocol's own doc comment already states
/// "backed today by nothing" — this type is that honest absence made
/// concrete, so a real session can be composed before retrieval for any of
/// the three exists. A future real implementation replaces this type at the
/// composition root; it never needs a change to ``ContextAssembler`` or to
/// the protocols themselves.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback
public struct InertContextSource: SpecDriveContextSource, BoardStateContextSource, MemoriesContextSource, Sendable {
    private let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public func fetch(for _: Intent) -> ContextFragment {
        .unavailable(reason: reason)
    }

    /// "Retrieval must be selective" is separate backlog work:
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#how-specs-are-retrieved
    public static let specDrive = Self(reason: "Spec Drive retrieval is not implemented yet (issue #82).")

    /// Reading live board state is separate backlog work:
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#board
    public static let board = Self(reason: "Board state retrieval is not implemented yet (issue #86).")

    /// Local persistent memory storage is separate backlog work:
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#local-persistent-memories
    public static let memories = Self(reason: "Local memories are not implemented yet (issue #105).")
}
