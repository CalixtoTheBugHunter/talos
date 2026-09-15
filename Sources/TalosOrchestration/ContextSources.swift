import TalosProjectLibrary

/// Retrieves indexed Spec Drive sections for one intent, selected lexically within the token budget.
///
/// The seam ``ContextAssembler`` assembles spec context through, per
/// [retrieving specs](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#how-specs-are-retrieved).
public protocol SpecDriveContextSource: Sendable {
    func fetch(for intent: Intent) -> ContextFragment
}

/// Retrieves live Board state for one intent. Backed today by nothing —
/// reading live board items is separate backlog work; this protocol is the
/// seam that work implements against.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#board
public protocol BoardStateContextSource: Sendable {
    func fetch(for intent: Intent) -> ContextFragment
}

/// Retrieves relevant local memories for one intent. Backed today by
/// nothing — local persistent memory storage is separate backlog work; this
/// protocol is the seam that work implements against.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#local-persistent-memories
public protocol MemoriesContextSource: Sendable {
    func fetch(for intent: Intent) -> ContextFragment
}
