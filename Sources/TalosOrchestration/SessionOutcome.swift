import TalosAdapters
import TalosProjectLibrary

/// How one session ended. Every path out of the pipeline lands on exactly one
/// case, including the two that never launch an agent, so no terminal state
/// is left without a record.
///
/// `.denied` and `.stopped` are their own cases rather than kinds of
/// `.failed`: "Denial is not failure" — a denied session is rendered as
/// denied, never as an error, and a user stop is not one either.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model
public enum SessionOutcome: Equatable, Sendable {
    /// The pinned context alone exceeded the ceiling, so stage 3 never
    /// produced a prompt. Failed, not denied — nothing was gated.
    case contextAssemblyFailed(ContextAssemblyFailure)
    /// Stage 4 refused the session before any agent was launched.
    case safeguardsPreCheckDenied(reason: String)
    case succeeded(TokenReport)
    /// The agent exited non-zero or never launched — including a crash, where
    /// `tokenReport` is whatever the adapter could still report.
    case failed(reason: String, tokenReport: TokenReport)
    case stopped(TokenReport)
    case denied(TokenReport)
}

/// The row one finished session writes, exactly once.
///
/// Deliberately minimal: it carries the project, the sub-function, and the
/// outcome — which is also what stage 10 owes the Monitor Screen, since
/// `SessionOutcome` carries the ``TokenReport``. The richer schema
/// (durations, tool-call and approval counts, queryability) is tracked
/// separately.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model
public struct SessionRecord: Equatable, Sendable {
    public let project: ProjectIdentifier
    public let subFunction: SubFunction
    public let outcome: SessionOutcome

    public init(project: ProjectIdentifier, subFunction: SubFunction, outcome: SessionOutcome) {
        self.project = project
        self.subFunction = subFunction
        self.outcome = outcome
    }
}

/// Stage 9, "session record written". Non-throwing on purpose: a write that
/// could fail and be swallowed would break "exactly once", and a write that
/// could throw would let a persistence fault rewrite the session's outcome.
/// Retry and durability belong to the implementation.
public protocol SessionRecordWriter: Sendable {
    func write(_ record: SessionRecord) async
}

/// Stage 11, "memories updated" — the write side of the read-only
/// ``MemoriesContextSource`` a session's context is assembled from. Runs after
/// the record for every terminal state, so a denied or stopped session
/// updates memories on the same path a successful one does.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model
public protocol SessionMemoriesUpdatePort: Sendable {
    func updateMemories(for record: SessionRecord) async
}
