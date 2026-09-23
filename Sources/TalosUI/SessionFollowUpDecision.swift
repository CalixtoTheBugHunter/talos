/// What to do with a message the user submits into the session the console
/// shows. A message always reaches the agent: if a turn is running it
/// *interrupts* that turn and supersedes it, rather than waiting behind it; if
/// none is running it is sent at once. Whether the message resumes the same
/// session or starts a fresh one turns on whether a resume token exists — a
/// brand-new session's first turn has none until the agent emits its id, and a
/// message that lands before then starts fresh, since the aborted turn produced
/// nothing to preserve.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
public enum SessionFollowUpDecision: Equatable, Sendable {
    /// A turn is running: stop it (denying any pending approval) and resume the
    /// same session with the message once it has torn down.
    case interruptThenResume
    /// A turn is running but no resume token exists yet: stop it and start a
    /// fresh session with the message as its opening intent.
    case interruptThenFreshStart
    /// No turn is running and the session is resumable: send the message at once.
    case resumeNow
    /// No turn is running and nothing is resumable: start a fresh session.
    case freshStartNow

    public static func decide(isTurnRunning: Bool, hasResumeToken: Bool) -> Self {
        switch (isTurnRunning, hasResumeToken) {
        case (true, true): .interruptThenResume
        case (true, false): .interruptThenFreshStart
        case (false, true): .resumeNow
        case (false, false): .freshStartNow
        }
    }
}
