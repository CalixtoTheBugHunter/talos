import Observation
import TalosAdapters
import TalosCore
import TalosSafeguards

/// One request the view is showing right now.
public struct PendingApproval: Identifiable, Equatable, Sendable {
    public let id: String
    public let request: AgentPermissionRequest
    public let action: SafeguardsActionType
    public let tier: SafeguardsTier
}

/// One request waiting for a decision, holding the continuation ``ApprovalPromptCenter/present(_:action:tier:)``
/// is suspended on until ``ApprovalPromptCenter/resolve(_:with:)`` or cancellation answers it.
private struct QueuedApproval {
    let pending: PendingApproval
    let continuation: CheckedContinuation<AgentPermissionDecision?, Never>
}

/// The SwiftUI-backed ``SafeguardsApprovalPrompt``.
///
/// Concurrent sessions can each raise a request and the protocol carries no
/// session identifier to route by, so requests queue FIFO and only the head
/// is ever published as ``current`` — never two prompts competing for the one
/// interruption the SPEC sanctions.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#focus
@Observable
@MainActor
public final class ApprovalPromptCenter: SafeguardsApprovalPrompt {
    public private(set) var current: PendingApproval?

    private var queue: [QueuedApproval] = []

    public init() {
        // Nothing to seed — no pending prompt is restored at launch.
    }

    /// Suspends until ``resolve(_:with:)`` answers, or returns `nil` if the
    /// calling task is cancelled first — the fail-closed case the gate
    /// attributes to Talos rather than to a decision the user never made.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed
    public func present(
        _ request: AgentPermissionRequest,
        action: SafeguardsActionType,
        tier: SafeguardsTier
    ) async -> AgentPermissionDecision? {
        let pending = PendingApproval(id: request.id, request: request, action: action, tier: tier)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<AgentPermissionDecision?, Never>) in
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                enqueue(QueuedApproval(pending: pending, continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(pending.id) }
        }
    }

    /// Called by the presented view once the user decides.
    public func resolve(_ id: String, with decision: AgentPermissionDecision) {
        complete(id, with: decision)
    }

    private func cancel(_ id: String) {
        complete(id, with: nil)
    }

    private func complete(_ id: String, with outcome: AgentPermissionDecision?) {
        guard let index = queue.firstIndex(where: { $0.pending.id == id }) else { return }
        let approval = queue.remove(at: index)
        if current?.id == id {
            showNext()
        }
        approval.continuation.resume(returning: outcome)
    }

    private func enqueue(_ approval: QueuedApproval) {
        queue.append(approval)
        if queue.count == 1 {
            showNext()
        }
    }

    private func showNext() {
        current = queue.first?.pending
    }
}
