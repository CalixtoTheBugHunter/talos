import TalosAdapters
import TalosSafeguards

/// The per-event handlers `consume`'s loop delegates to — split out to keep
/// both that loop and the `SafeguardsApproved` body within this module's
/// length limits.
extension SafeguardsApproved {
    /// Tallies a `.toolCall` into `metrics` and `transcript`.
    func note(
        _ call: AgentToolCall,
        metrics: inout SessionRunMetrics,
        transcript: inout [SessionTranscriptEntry],
        retries: inout RetryTracker
    ) {
        metrics.toolCallCount += 1
        if retries.noteToolCall(call) {
            metrics.retryCount += 1
        }
        transcript.append(.toolCall(id: call.id, name: call.name, targets: call.targets))
    }

    /// Fails closed an action the gate can never be offered — one the adapter
    /// held but the CLI carried back no way to answer. The gate denies without
    /// prompting; the decision is logged with the same four fields as any
    /// other, actor Talos, and the user gets the same denial indication a
    /// blocked repeat gets. The adapter, not this, tells the agent, so there is
    /// nothing to resolve back and the session continues.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed
    func carryUnaskable(
        _ request: AgentPermissionRequest,
        collaborators: SessionRunCollaborators<some AgentAdapter, some SafeguardsGate>,
        metrics: inout SessionRunMetrics,
        retries: inout RetryTracker
    ) async {
        let decision = await collaborators.gate.denyUnaskable(
            request,
            project: intent.project,
            subFunction: intent.requestingSubFunction
        )
        metrics.denialCount += 1
        retries.noteDenial(of: request.id, action: decision.action, classification: decision.classification)
        await collaborators.onDenial?(decision.action, request.prompt)
        await collaborators.decisionLog.record(GatedDecisionEntry(
            project: intent.project,
            sessionID: collaborators.sessionID,
            timestamp: collaborators.now(),
            subFunction: intent.requestingSubFunction,
            request: request,
            decision: decision
        ))
    }
}
