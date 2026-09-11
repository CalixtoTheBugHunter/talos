import TalosAdapters
import TalosCore

/// The mutable tally `SafeguardsApproved.consume` threads through each event:
/// the agent's last chunk (a crash carries no termination event of its own to
/// carry the agent's final words), the metrics, the transcript, and the
/// denied-action signatures a later retry is matched against. Bundled so
/// `consume` and `process` share one `inout` value rather than four.
struct SessionRunProgress {
    var lastOutput = ""
    var metrics = SessionRunMetrics()
    var transcript: [SessionTranscriptEntry] = []
    var retries = RetryTracker()
}

/// The next thing a session read produced: an event, the stream ending, or the
/// response-liveness interval elapsing with neither.
enum NextSessionEvent: Sendable {
    case event(AgentEvent)
    case timedOut
    case ended
}

/// Owns one session's event iterator so a deadline can race `read()` from a
/// child task. An ``AgentEventStream`` iterator is not `Sendable`, so it is
/// held in a reference type marked `@unchecked Sendable`: access is genuinely
/// serial — `next(timeout:)` starts exactly one reader child, and `consume`
/// awaits each `next(timeout:)` fully before the next, so no two `read()` calls
/// are ever in flight — which an actor cannot express here, because a
/// `mutating async next()` may not be called on an isolated stored property.
final class AgentEventReader: @unchecked Sendable {
    private var iterator: AgentEventStream.AsyncIterator

    init(_ stream: AgentEventStream) {
        iterator = stream.makeAsyncIterator()
    }

    /// The next event, `.ended` when the stream finished, or `.timedOut` when
    /// none arrived within `timeout`. Only the silence *between* events is
    /// timed: the caller runs the Safeguards gate in its own loop body, never
    /// inside this call, so a pending prompt is never on this clock — "a
    /// pending prompt has no timer" is unchanged. Decision 81.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
    func next(timeout: Duration) async throws -> NextSessionEvent {
        try await withThrowingTaskGroup(of: NextSessionEvent.self) { group in
            group.addTask { [self] in
                guard let event = try await read() else { return .ended }
                return .event(event)
            }
            group.addTask {
                // `try?`: a cancel here is the event winning the race, not a
                // failure — the harmless `.ended` it then returns is discarded.
                try? await Task.sleep(for: timeout)
                return Task.isCancelled ? .ended : .timedOut
            }
            let first = try await group.next() ?? .ended
            group.cancelAll()
            return first
        }
    }

    private func read() async throws -> AgentEvent? {
        try await iterator.next()
    }
}

/// Names the interval that elapsed — failure copy states what failed and in
/// what state; the agent's own last output is carried separately by `abandon`.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice
func timedOutReason(_ timeout: Duration) -> String {
    "The agent produced no response for \(timeout.components.seconds) seconds."
}
