import TalosAdapters
import TalosProjectLibrary
import TalosSafeguards

/// Decides whether an allowed board write proceeds, or is abandoned because the
/// item diverged from the state Talos read — decision 42's detect-and-ask,
/// realized on the agent's gated write per
/// [decision 94](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions).
/// The gate has already allowed the action; this asks the separate question of
/// which of two states is correct, so it is never a Safeguards approval and an
/// allowlist on the write never suppresses it.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#when-a-human-and-talos-move-the-same-item
public protocol BoardConflictResolver: Sendable {
    /// Resolves one allowed permission request. ``BoardConflictResolution/proceed``
    /// when the request is not a board write, the states agreed, or the user
    /// chose to apply the move over the state they have now seen;
    /// ``BoardConflictResolution/abandon(actor:)`` when the user kept the
    /// human's state or opened the item (actor `.user`), or the prompt could
    /// not be presented and the write fails closed (actor `.talos`).
    func resolve(_ request: AgentPermissionRequest) async -> BoardConflictResolution
}

/// The outcome of a board conflict check on an allowed write.
public enum BoardConflictResolution: Equatable, Sendable {
    case proceed
    case abandon(actor: SafeguardsDecisionActor)
}

/// What a diverged item's prompt shows: the item as it really is now, the two
/// states that differ, and where Talos's move would put it. `item` carries who
/// changed it and when, when the read supplied them.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#when-a-human-and-talos-move-the-same-item
public struct BoardConflictPresentation: Equatable, Sendable {
    public let item: BoardItem
    public let expected: BoardState
    public let actual: BoardState
    public let targetColumn: String

    public init(item: BoardItem, expected: BoardState, actual: BoardState, targetColumn: String) {
        self.item = item
        self.expected = expected
        self.actual = actual
        self.targetColumn = targetColumn
    }
}

/// The user's answer to a conflict prompt — decision 42's three outcomes.
/// `↩` is bound to none of them: the safe one is not obvious.
public enum BoardConflictChoice: Equatable, Sendable {
    /// Keep the human's state — the write is abandoned, the agent told the
    /// item was superseded.
    case keepHumanState
    /// Apply Talos's move over the state the user has now seen.
    case applyMove
    /// Open the item; the write is abandoned and the item opens for the user
    /// to decide with full history.
    case openItem
}

/// The detect-and-ask resolver: recognizes a board write, reads "actual" out of
/// band, compares it against the "expected" state assembled into context, and
/// asks the user only when they diverge. All logic lives here; the app supplies
/// the out-of-band read and the prompt as closures, so this is testable with no
/// UI and no board client.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions
public struct DetectAndAskBoardConflictResolver: BoardConflictResolver {
    private let recognizer: BoardWriteRecognizer
    private let check: BoardConflictCheck
    private let expected: [BoardItem]
    private let fetchActual: @Sendable () async -> [BoardItem]
    private let present: @Sendable (BoardConflictPresentation) async -> BoardConflictChoice?

    public init(
        recognizer: BoardWriteRecognizer,
        check: BoardConflictCheck,
        expected: [BoardItem],
        fetchActual: @escaping @Sendable () async -> [BoardItem],
        present: @escaping @Sendable (BoardConflictPresentation) async -> BoardConflictChoice?
    ) {
        self.recognizer = recognizer
        self.check = check
        self.expected = expected
        self.fetchActual = fetchActual
        self.present = present
    }

    public func resolve(_ request: AgentPermissionRequest) async -> BoardConflictResolution {
        guard let write = recognizer.boardWrite(toolName: request.toolName, arguments: request.arguments) else {
            return .proceed
        }
        let actual = await fetchActual()
        guard case let .diverged(divergence) = check.evaluate(itemID: write.itemID, expected: expected, actual: actual)
        else {
            return .proceed
        }
        let presentation = BoardConflictPresentation(
            item: divergence.item,
            expected: divergence.expected,
            actual: divergence.actual,
            targetColumn: write.targetColumn
        )
        switch await present(presentation) {
        case .applyMove:
            return .proceed
        case .keepHumanState, .openItem:
            return .abandon(actor: .user)
        case nil:
            // The prompt could not be presented — the write fails closed, and
            // the denial is Talos's, not a choice the user made.
            return .abandon(actor: .talos)
        }
    }
}
