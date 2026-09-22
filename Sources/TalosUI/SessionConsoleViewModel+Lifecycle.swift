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

    /// Re-arms the running state for a resumed turn while keeping the
    /// transcript: clearing ``termination`` makes ``isRunning`` true again, and
    /// the follow-up's output appends to the lines the prior turn left rather
    /// than replacing them — "the follow-up turn's output appends to the
    /// existing transcript." Unlike ``sessionStarted()`` this clears no
    /// ``lines`` or ``tokenUsage``. A no-op before any session has started,
    /// since there is then nothing to continue.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
    func beginFollowUpTurn() {
        guard hasStarted else { return }
        termination = nil
        noteUnavailableContext([])
        resumeFollowingOutput()
    }

    /// Appends a message the user sent into the session, so the transcript
    /// reads as the whole conversation "from the first until the end of the
    /// workflow" rather than only the agent's half. Closes any open output line
    /// first — the user's turn is a complete unit interrupting the stream — and
    /// announces it once for VoiceOver, the same as a finalized output line.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
    func appendUserMessage(_ text: String) {
        closeOpenLineIfNeeded()
        lines.append(SessionConsoleLine(id: makeNextID(), content: .userMessage(text)))
        announceIfMeaningful(text)
    }

    /// What ``SessionConsoleView`` renders right now — derived rather than
    /// stored, so it can never drift from ``lines`` and ``termination``.
    /// A termination is checked before an empty transcript, so a session that
    /// failed or was denied before producing any output still reads as
    /// ``State/failed(_:)`` / ``State/denied(_:)`` rather than as stuck in
    /// ``State/loading``.
    var state: State {
        if let termination {
            switch termination.reason {
            case let .exited(code):
                return code == 0 ? (lines.isEmpty ? .empty : .ready) : .failed(termination)
            case .failedToLaunch:
                return .failed(termination)
            case .denied:
                return .denied(termination)
            case .stopped:
                return lines.isEmpty ? .empty : .ready
            }
        }
        if lines.isEmpty {
            return hasStarted ? .loading : .empty
        }
        return .ready
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
