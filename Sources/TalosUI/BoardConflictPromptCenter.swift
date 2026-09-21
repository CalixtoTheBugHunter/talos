import Observation
import TalosOrchestration

/// One diverged item the conflict prompt is showing right now.
public struct PendingBoardConflict: Identifiable, Equatable, Sendable {
    /// A fresh handle, not the item id: two sessions may diverge on the same
    /// item, and the continuation is routed by this.
    public let id: String
    public let presentation: BoardConflictPresentation
}

/// One diverged item waiting for a choice, holding the continuation
/// ``BoardConflictPromptCenter/present(_:)`` is suspended on.
private struct QueuedBoardConflict {
    let pending: PendingBoardConflict
    let continuation: CheckedContinuation<BoardConflictChoice?, Never>
}

/// The SwiftUI-backed presenter for the board conflict prompt — decision 42's
/// detect-and-ask. It is **not** a Safeguards approval and never stands in for
/// one: the gate asks whether Talos may act, this asks which of two states is
/// correct. It blocks the session the same way the gate does — no timer,
/// cancellable by Stop, and a dismissal it did not drive abandons the write
/// rather than assuming a state. Mirrors ``ApprovalPromptCenter``'s continuation
/// bridge; requests queue FIFO so only one prompt is ever shown.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#when-a-human-and-talos-move-the-same-item
@Observable
@MainActor
public final class BoardConflictPromptCenter {
    /// The conflict the view is showing right now, or `nil` when none is
    /// pending — the only one presented, even if more are queued behind it.
    public private(set) var current: PendingBoardConflict?

    private var queue: [QueuedBoardConflict] = []
    private var nextID = 0

    /// Starts with no pending prompt — none is restored at launch.
    public init() {
        // Nothing to seed.
    }

    /// Suspends until the user chooses, returns `nil` if the task is cancelled
    /// first (⌘. / Stop) — the write is then abandoned rather than assuming a
    /// state, and the abandon is attributed to Talos, not to a choice the user
    /// never made.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed
    public func present(_ presentation: BoardConflictPresentation) async -> BoardConflictChoice? {
        nextID += 1
        let pending = PendingBoardConflict(id: "\(nextID)", presentation: presentation)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<BoardConflictChoice?, Never>) in
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                enqueue(QueuedBoardConflict(pending: pending, continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.failClosed(pending.id) }
        }
    }

    /// Called by the presented view once the user chooses.
    public func resolve(_ id: String, with choice: BoardConflictChoice) {
        complete(id, with: choice)
    }

    /// Called when the prompt cannot be presented or its window is dismissed by
    /// something other than a choice — the write is abandoned, fail-closed.
    public func failClosed(_ id: String) {
        complete(id, with: nil)
    }

    private func complete(_ id: String, with choice: BoardConflictChoice?) {
        guard let index = queue.firstIndex(where: { $0.pending.id == id }) else { return }
        let queued = queue.remove(at: index)
        if current?.id == id {
            showNext()
        }
        queued.continuation.resume(returning: choice)
    }

    private func enqueue(_ conflict: QueuedBoardConflict) {
        queue.append(conflict)
        if queue.count == 1 {
            showNext()
        }
    }

    private func showNext() {
        current = queue.first?.pending
    }
}
