import TalosAdapters
import TalosProjectLibrary

/// The gate every mutating tool call passes through mid-session, at stages
/// 6-8 of the shared session model: "each mutating tool call hits the
/// Safeguards gate → approve / deny".
///
/// `decide` returns rather than throws, because there is no third answer: a
/// gate that cannot reach the user returns `.denied`, it does not fail. It is
/// `async` with no deadline in the signature for the same reason — an
/// unanswered request waits, and nothing here can time one out into an
/// allow.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy
///
/// Declared here with no conformance in this module: tiers, the versioned
/// action taxonomy, allowlisting, and the approval UI are tracked separately.
public protocol SafeguardsGate: Sendable {
    func decide(
        _ request: AgentPermissionRequest,
        project: ProjectIdentifier,
        subFunction: SubFunction
    ) async -> AgentPermissionDecision
}
