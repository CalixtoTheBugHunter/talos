import TalosAdapters
import TalosProjectLibrary

/// The gate every mutating action passes through mid-session, at stages 6-8 of
/// the shared session model: "each mutating tool call hits the Safeguards gate
/// → approve / deny".
///
/// What reaches it is an ``AgentPermissionRequest`` — an action an adapter is
/// **holding** before it runs. An ``AgentToolCall`` is the agent announcing a
/// call, which is a console event and never a decision point; the two stay
/// distinct events, and an adapter that announces a mutating call without also
/// holding it has left this gate nothing to intercept. That is a defect in
/// that adapter, not a case for core to guess at by reading a tool name.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
///
/// `decide` returns rather than throws, because there is no third answer: a
/// gate that cannot reach the user denies, it does not fail. It is `async`
/// with no deadline in the signature for the same reason — an unanswered
/// request waits, and nothing here can time one out into an allow.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed
///
/// **Cancellation is the one thing that ends the wait**, and a conformance ends
/// it in a denial attributed to ``SafeguardsDecisionActor/talos``: the session
/// is being torn down, so the gate can no longer obtain a decision, and a
/// denial recorded against the user is one they never made.
///
/// Declared here with no conformance in this module: tiers, the versioned
/// action taxonomy, allowlisting, and the approval UI are tracked separately.
public protocol SafeguardsGate: Sendable {
    func decide(
        _ request: AgentPermissionRequest,
        project: ProjectIdentifier,
        subFunction: SubFunction
    ) async -> SafeguardsDecision
}
