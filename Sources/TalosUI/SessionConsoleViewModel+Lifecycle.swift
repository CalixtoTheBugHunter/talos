import TalosAdapters
import TalosOrchestration

/// Session-lifecycle helpers — split out of `SessionConsoleViewModel.swift`
/// because that file, holding every streaming behaviour plus these, ran past
/// this module's own file-length limit (the same reason `+Resume` is split).
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
public extension SessionConsoleViewModel {
    /// Whether a session is live — started and not yet terminated. Drives the
    /// in-console Stop control's visibility, from the same state that renders
    /// the loading and streaming views, so the control appears exactly while
    /// the session is actually running.
    var isRunning: Bool {
        hasStarted && termination == nil
    }

    /// Reflects the pipeline's final outcome for a session that ended without a
    /// `.terminated` ever reaching the stream — a launch that failed, a
    /// context-assembly overflow, or a pre-check denial, none of which produce
    /// one. A no-op once the stream already reported the end, so a normal or
    /// mid-run outcome keeps the termination it observed.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#errors
    func sessionConcluded(_ outcome: SessionOutcome) {
        guard hasStarted, termination == nil else { return }
        let reason: AgentTerminationReason = switch outcome {
        case .succeeded: .exited(code: 0)
        case .stopped: .stopped
        case .denied, .safeguardsPreCheckDenied: .denied
        case .failed, .contextAssemblyFailed: .failedToLaunch
        }
        termination = AgentTermination(reason: reason)
    }
}
