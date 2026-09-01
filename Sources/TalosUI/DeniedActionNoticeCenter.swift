import Foundation
import Observation
import TalosCore

/// One denial the user is being shown right now — the counterpart of
/// ``PendingApproval`` for the case where nothing was asked before the
/// action was denied.
public struct DeniedActionNotice: Identifiable, Equatable, Sendable {
    public let id: String
    public let action: SafeguardsActionType
    public let requestPrompt: String
}

/// Shows a transient, non-alarming trace of a denial that reached the agent
/// without a fresh prompt — a fail-closed denial, or a repeat of a signature
/// already denied this session. ``ApprovalPromptCenter`` has no state for
/// either case, since neither one asks the user anything; this is what makes
/// that denial visible in the moment it happened rather than only in a log.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#denial-is-not-failure
@Observable
@MainActor
public final class DeniedActionNoticeCenter {
    private static let defaultDismissAfterSeconds = 4

    /// How long a notice stays up before ``notify(action:requestPrompt:)``
    /// clears it on its own, absent a caller-supplied duration.
    public static let defaultDismissAfter: Duration = .seconds(defaultDismissAfterSeconds)

    /// The notice on screen right now, if any.
    public private(set) var current: DeniedActionNotice?

    private let dismissAfter: Duration
    private var dismissTask: Task<Void, Never>?

    /// `dismissAfter` is overridable so a test can assert the auto-dismiss
    /// without waiting out the real duration.
    public init(dismissAfter: Duration = defaultDismissAfter) {
        self.dismissAfter = dismissAfter
    }

    /// Shows `action` as denied, replacing whatever notice is currently
    /// showing, then clears itself after `dismissAfter` — a single scheduled
    /// dismissal, never a timer that wakes to poll.
    public func notify(action: SafeguardsActionType, requestPrompt: String) async {
        let notice = DeniedActionNotice(id: UUID().uuidString, action: action, requestPrompt: requestPrompt)
        current = notice
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self, dismissAfter] in
            try? await Task.sleep(for: dismissAfter)
            guard let self, !Task.isCancelled, current?.id == notice.id else { return }
            current = nil
        }
    }
}
