import Foundation
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
        tokenOverheadRatio: Double
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
    }
}
