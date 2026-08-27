/// The whole set of context parts a session assembles: "Editable Talos
/// Guidelines, Spec Drive, Connectors, Board state, Safeguards, and
/// relevant memories." Raw values match exactly the identifiers a
/// guideline's own `context:` front-matter field names
/// (``GuidelineDocument/context``) — `spec-drive`, `connectors`, `board`,
/// `memories` — so mapping a guideline's request onto a part is a lookup,
/// never a guess. Root Talos Guidelines are deliberately absent from this
/// set: it is never assembled, so no case here can name it.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#editable-talos-guidelines
public enum ContextPartKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case guideline
    case safeguards
    case specDrive = "spec-drive"
    case connectors
    case board
    case memories
}

public extension ContextPartKind {
    /// The two parts that are never dropped: "The sub-function's own
    /// guideline and the Safeguards copy are never dropped."
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#when-assembled-context-exceeds-the-ceiling
    var isPinned: Bool {
        switch self {
        case .guideline, .safeguards: true
        case .specDrive, .connectors, .board, .memories: false
        }
    }

    /// The compiled-in default drop order, first dropped to last —
    /// per [decision 47](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions):
    /// "memories, board, connectors, spec-drive". Per
    /// [decision 78](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions),
    /// this is the *only* order today — `.talos/safeguards.md` declares no
    /// machine-readable override, and none is parsed from it.
    static let dropOrder: [ContextPartKind] = [.memories, .board, .connectors, .specDrive]
}

/// One context part's content, or the declared reason it has none. Distinct
/// from a part being *dropped* for exceeding the ceiling — this is about a
/// part that was never available to include in the first place, per
/// "missing context is labeled where the output is read".
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback
public enum ContextFragment: Equatable, Sendable {
    case available(String)
    case unavailable(reason: String)
}
