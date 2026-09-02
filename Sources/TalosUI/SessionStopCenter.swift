import Observation

/// Tracks whether a session is running right now, and how to stop it — the
/// state a visible Stop control and the app-scoped `⌘.` command both bind to.
///
/// Mirrors ``ApprovalPromptCenter``'s shape, and built the same way and for
/// the same reason: before a Session Console exists to host a per-session
/// control, this is what makes "stop is always reachable at `⌘.`, always
/// visible while a session runs" checkable now rather than deferred. See
/// § The stop guarantee is an interaction rule:
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard
@Observable
@MainActor
public final class SessionStopCenter {
    /// Whether a session is running right now — what the visible control and
    /// the menu command's enabled state both read.
    public private(set) var isSessionRunning = false

    private var stopHandler: (@Sendable () async -> Void)?

    /// No session is running at launch, so there is nothing to seed.
    public init() {
        // Nothing to seed — no session is running at launch.
    }

    /// Called once a session starts, naming how to stop *this* one. Only one
    /// session is ever tracked: "`⌘.` stops the session the sidebar has
    /// selected. One selection, so one target."
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#stop-stays-reachable
    public func beginTracking(stopping stopHandler: @escaping @Sendable () async -> Void) {
        self.stopHandler = stopHandler
        isSessionRunning = true
    }

    /// Called once the session reaches its own terminal state, whether or not
    /// a stop caused it — a session that ended on its own is no longer a
    /// target either.
    public func sessionEnded() {
        stopHandler = nil
        isSessionRunning = false
    }

    /// What the visible control and the `⌘.` command both call. Never blocks
    /// the caller: the actual kill runs on its own task, since a stop that
    /// froze the UI while it ran would fail the < 100 ms first-feedback
    /// budget on the one control that most needs to feel instant.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable
    public func requestStop() {
        guard let stopHandler else { return }
        Task { await stopHandler() }
    }
}
