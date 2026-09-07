import Foundation
import TalosAdapters
import TalosCore
import TalosSafeguards

/// Everything ``SafeguardsApproved/run`` needs to route one session, bundled
/// so `consume`/`carry` take one parameter for all six instead of six — the
/// shape this module's own `function_parameter_count` limit forces, and a
/// reasonable one: the six never vary independently within a single run.
struct SessionRunCollaborators<Adapter: AgentAdapter, Gate: SafeguardsGate> {
    let adapter: Adapter
    let gate: Gate
    let decisionLog: any GatedDecisionLog
    let sessionID: UUID
    let now: @Sendable () -> Date
    let onDenial: (@Sendable (SafeguardsActionType, String) async -> Void)?
}

/// What one session accumulated while stages 5-8 ran: tool calls observed,
/// gated decisions carried back, and retries of an already-denied action.
/// Zero for the two stages that never reach ``SafeguardsApproved`` at all —
/// a context-assembly failure or a pre-check denial has nothing here to
/// count.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen
public struct SessionRunMetrics: Equatable, Sendable {
    public var toolCallCount = 0
    public var approvalCount = 0
    public var denialCount = 0
    public var retryCount = 0

    public init(
        toolCallCount: Int = 0,
        approvalCount: Int = 0,
        denialCount: Int = 0,
        retryCount: Int = 0
    ) {
        self.toolCallCount = toolCallCount
        self.approvalCount = approvalCount
        self.denialCount = denialCount
        self.retryCount = retryCount
    }
}

/// What ``SafeguardsApproved/run(launchConfiguration:adapter:gate:decisionLog:observer:onDenial:)``
/// produces: the terminal ``SessionOutcome``, the metrics accumulated
/// reaching it, the transcript observed, and this run's own resume token —
/// "sessions are resumable, and output is copyable and exportable."
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
public struct SessionRunOutcome: Sendable {
    public let outcome: SessionOutcome
    public let metrics: SessionRunMetrics
    public let transcript: [SessionTranscriptEntry]
    /// This run's own opaque continuation identifier, carried from the
    /// terminating ``AgentTermination/resumeToken`` when one was read. `nil`
    /// for an adapter with none, or a degraded ending that never read the
    /// adapter's own `.terminated` event — see
    /// ``SafeguardsApproved/stop(adapter:metrics:transcript:)``.
    public let resumeToken: String?

    public init(
        outcome: SessionOutcome,
        metrics: SessionRunMetrics,
        transcript: [SessionTranscriptEntry] = [],
        resumeToken: String? = nil
    ) {
        self.outcome = outcome
        self.metrics = metrics
        self.transcript = transcript
        self.resumeToken = resumeToken
    }
}
