import TalosAdapters
import TalosCore

/// Presents one write- or irreversible-tier action to the user and carries
/// back the answer, for the gate to call when no allowlist already settles
/// it.
///
/// Returns `nil` for the two cases [the gate fails
/// closed](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed)
/// names as denials — the prompt could not be presented, or the user could
/// not be reached at all — never for "not answered yet": that case is
/// ordinary suspension, since this method is `async` with no deadline and
/// waits as long as the user needs. A conformance ends the wait early only on
/// cancellation, per the same rule the gate itself follows.
///
/// Declared here with no conformance in this module: the approval UI — its
/// copy, controls, and keyboard bindings — is tracked separately.
public protocol SafeguardsApprovalPrompt: Sendable {
    func present(
        _ request: AgentPermissionRequest,
        action: SafeguardsActionType,
        tier: SafeguardsTier
    ) async -> AgentPermissionDecision?
}
