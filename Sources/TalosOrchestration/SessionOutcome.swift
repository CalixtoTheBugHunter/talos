import Foundation
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
    ///
    /// `lastOutput` is the agent's own final words, carried rather than
    /// summarized: failure copy names "what failed, where, and what state
    /// things are in", and a message that drops the state clause sends the user
    /// to a terminal to learn what Talos already knew. Empty when the agent
    /// produced none.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice
    case failed(reason: String, lastOutput: String = "", tokenReport: TokenReport)
    case stopped(TokenReport)
    case denied(TokenReport)
}

/// The four-value outcome taxonomy the Monitor Screen and the success-rate
/// formula read, settled by
/// [decision 60](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions):
/// "Inferred from the session's end state and typed as `Succeeded`, `Failed`,
/// `Denied`, or `Stopped`."
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-task-outcome-is-classified
public enum SessionOutcomeClassification: String, Equatable, Sendable, CaseIterable {
    case succeeded
    case failed
    case denied
    case stopped
}

public extension SessionOutcome {
    /// This session's outcome, collapsed onto the four values the Monitor
    /// Screen and the success rate read. `.contextAssemblyFailed` is
    /// `.failed` per
    /// [decision 47](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions) —
    /// "nothing was gated, so recording a denial would name a decision nobody
    /// made" — and `.safeguardsPreCheckDenied` is `.denied`: the session
    /// ended because the gate denied and the work could not continue, which
    /// is exactly
    /// [decision 60](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions)'s
    /// definition of `Denied`.
    var classification: SessionOutcomeClassification {
        switch self {
        case .contextAssemblyFailed: .failed
        case .safeguardsPreCheckDenied: .denied
        case .succeeded: .succeeded
        case .failed: .failed
        case .stopped: .stopped
        case .denied: .denied
        }
    }
}

/// The row one finished session writes, exactly once.
///
/// Deliberately minimal: it carries the project, the sub-function, the outcome
/// — which is also what stage 10 owes the Monitor Screen, since
/// `SessionOutcome` carries the ``TokenReport`` — and what stage 3 could not
/// fit. The richer schema (durations, tool-call and approval counts,
/// queryability) is tracked separately.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model
public struct SessionRecord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let project: ProjectIdentifier
    public let subFunction: SubFunction
    /// The `agents.yaml` entry this session ran on. Nothing upstream of the
    /// pipeline carries it, so the caller that already knows which declared
    /// agent it launched supplies it here, bundled with `SessionLaunch`.
    public let agentName: String
    public let outcome: SessionOutcome
    /// When stage 1 received the intent, and how long the whole run took —
    /// what a query scoped to a time range reads.
    public let startedAt: Date
    public let duration: TimeInterval
    /// `.toolCall` events observed on the stream, gated decisions carried
    /// back, and same-signature retries of an already-denied action — see
    /// ``SessionRunMetrics``.
    public let toolCallCount: Int
    public let approvalCount: Int
    public let denialCount: Int
    public let retryCount: Int
    /// Talos-added token overhead for this session —
    /// ``AssembledContext/overheadRatio``, or `0` when stage 3 never produced
    /// a context to measure. Not a guess: a session with no assembled context
    /// truly added zero tokens.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable
    public let tokenOverheadRatio: Double
    /// Context parts dropped to satisfy the ceiling, and parts that had nothing
    /// to assemble. Both travel with the record because a dropped part is
    /// reported "on the output, in the session, and on the Monitor" — a session
    /// that ran on less context than it asked for and did not say so has
    /// dropped it silently.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#when-assembled-context-exceeds-the-ceiling
    public let droppedContextParts: [DroppedContextPart]
    public let unavailableContextParts: [UnavailableContextPart]
    /// This session's transcript, in arrival order — "output is copyable and
    /// exportable", and, on ``SQLiteSessionRecordStore``, what a resume or an
    /// export reads back. Empty for the two stages that never reach
    /// ``SafeguardsApproved`` — a context-assembly failure or a pre-check
    /// denial never launched an agent to have one.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
    public let transcript: [SessionTranscriptEntry]
    /// This session's own opaque continuation identifier, when the agent
    /// adapter reported one — "resuming uses the agent's own resume mechanism
    /// where available." `nil` for an adapter with none, and for the two
    /// stages that never launch an agent.
    public let resumeToken: String?

    public init(
        id: UUID,
        project: ProjectIdentifier,
        subFunction: SubFunction,
        agentName: String,
        outcome: SessionOutcome,
        startedAt: Date,
        duration: TimeInterval,
        toolCallCount: Int,
        approvalCount: Int,
        denialCount: Int,
        retryCount: Int,
        tokenOverheadRatio: Double,
        droppedContextParts: [DroppedContextPart] = [],
        unavailableContextParts: [UnavailableContextPart] = [],
        transcript: [SessionTranscriptEntry] = [],
        resumeToken: String? = nil
    ) {
        self.id = id
        self.project = project
        self.subFunction = subFunction
        self.agentName = agentName
        self.outcome = outcome
        self.startedAt = startedAt
        self.duration = duration
        self.toolCallCount = toolCallCount
        self.approvalCount = approvalCount
        self.denialCount = denialCount
        self.retryCount = retryCount
        self.tokenOverheadRatio = tokenOverheadRatio
        self.droppedContextParts = droppedContextParts
        self.unavailableContextParts = unavailableContextParts
        self.transcript = transcript
        self.resumeToken = resumeToken
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
