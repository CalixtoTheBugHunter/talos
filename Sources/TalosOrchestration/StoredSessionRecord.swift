import Foundation
import TalosAdapters
import TalosProjectLibrary

/// One session record as read back from storage — the Monitor Screen's read
/// model, not the pipeline's write-side ``SessionRecord``. Deliberately
/// leaner: it carries the four-value ``SessionOutcomeClassification`` rather
/// than the rich ``SessionOutcome`` (whose `lastOutput` and per-case payload
/// are not persisted), so a query never promises data storage does not keep.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen
public struct StoredSessionRecord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let project: ProjectIdentifier
    public let subFunction: SubFunction
    public let agentName: String
    public let outcome: SessionOutcomeClassification
    public let startedAt: Date
    public let duration: TimeInterval
    public let toolCallCount: Int
    public let approvalCount: Int
    public let denialCount: Int
    public let retryCount: Int
    public let tokenOverheadRatio: Double
    /// This session's own opaque continuation identifier, when the agent
    /// adapter reported one at the time — what a resume launches into.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
    public let resumeToken: String?
    /// What the adapter reported for this session's token usage, or `nil` when
    /// no token row was recorded. The counts and model the Monitor's cost
    /// estimate is mapped from — an unparsable count stays absent and named,
    /// never a stored zero.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured
    public let tokenReport: TokenReport?
    /// What Talos injected into this session by source, or `nil` for a session
    /// recorded before this was kept — such a session cannot be measured for
    /// overhead and is excluded and counted, never read as zero.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-token-overhead-is-computed
    public internal(set) var injectedTokens: InjectedTokens?

    public init(
        id: UUID,
        project: ProjectIdentifier,
        subFunction: SubFunction,
        agentName: String,
        outcome: SessionOutcomeClassification,
        startedAt: Date,
        duration: TimeInterval,
        toolCallCount: Int,
        approvalCount: Int,
        denialCount: Int,
        retryCount: Int,
        tokenOverheadRatio: Double,
        resumeToken: String? = nil,
        tokenReport: TokenReport? = nil,
        injectedTokens: InjectedTokens? = nil
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
        self.resumeToken = resumeToken
        self.tokenReport = tokenReport
        self.injectedTokens = injectedTokens
    }
}
