import TalosProjectLibrary

/// Retrieves Spec Drive content for one intent. Backed today by nothing —
/// [indexing and retrieval](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#how-specs-are-retrieved)
/// is separate backlog work; this protocol is the seam that work implements
/// against, so ``ContextAssembler`` is complete and testable now and needs
/// no change once a real implementation lands.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#spec-drive
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
