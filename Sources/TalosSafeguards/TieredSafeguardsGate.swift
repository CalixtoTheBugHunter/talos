import TalosAdapters
import TalosCore
import TalosProjectLibrary

/// The gate's own decision logic: classify, then settle the outcome per
/// [tier](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#tiers)
/// without ever widening one.
///
/// - Refused resolves immediately, actor Talos, and never reaches
///   `approvalPrompt` — an approval path is exactly what a refused type must
///   never have.
///   https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#refused--not-a-tier
/// - Write tier checks `allowlist` first; a hit resolves without a prompt,
///   actor Talos — an allowlisted pass is still a gated decision, decided by
///   Talos rather than asked of the user.
/// - Irreversible tier never consults `allowlist` at all, so nothing here can
///   make one allowlistable by mistake: "not allowlistable, ever."
/// - Read tier resolves allowed without a prompt. A held action reaching the
///   gate at read tier should not occur — an adapter holds only mutating
///   calls — but the classifier's own contract is that an action is
///   classified explicitly and never falls through, so this case is handled
///   rather than treated as unreachable.
/// - Whatever needs a prompt calls `approvalPrompt.present`. A `nil` answer —
///   presentation failed, or the user could not be reached — resolves denied,
///   actor Talos: "a gate that cannot obtain a decision denies."
///   https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed
///
/// The action type is read from `request.toolName`, which is the adapter's
/// own tool name rather than a taxonomy name until an adapter classifies its
/// own calls — a future, adapter-specific change tracked separately. Until
/// then a name absent from the taxonomy classifies as irreversible, which is
/// the classifier's designed-for safe default, not a defect of this gate.
///
/// Takes no guideline, intent, or session-instruction text as input, so
/// nothing carried in a prompt or a guideline can reach this decision at
/// all — the structural form of "the gate cannot be disabled by config,
/// guideline, or session instruction."
public struct TieredSafeguardsGate: SafeguardsGate {
    private let allowlist: any SafeguardsAllowlist
    private let approvalPrompt: any SafeguardsApprovalPrompt

    public init(allowlist: any SafeguardsAllowlist, approvalPrompt: any SafeguardsApprovalPrompt) {
        self.allowlist = allowlist
        self.approvalPrompt = approvalPrompt
    }

    public func decide(
        _ request: AgentPermissionRequest,
        project: ProjectIdentifier,
        subFunction _: SubFunction
    ) async -> SafeguardsDecision {
        let action = SafeguardsActionType(rawValue: request.toolName ?? "")
        switch SafeguardsActionClassifier.classify(action) {
        case .refused:
            return SafeguardsDecision(outcome: .denied, action: action, classification: .refused, actor: .talos)
        case .tier(.read):
            return SafeguardsDecision(outcome: .allowed, action: action, classification: .tier(.read), actor: .talos)
        case .tier(.write):
            if await allowlist.isAllowlisted(action, project: project) {
                return SafeguardsDecision(
                    outcome: .allowed,
                    action: action,
                    classification: .tier(.write),
                    actor: .talos
                )
            }
            return await decideByPrompting(request, action: action, tier: .write)
        case .tier(.irreversible):
            return await decideByPrompting(request, action: action, tier: .irreversible)
        }
    }

    private func decideByPrompting(
        _ request: AgentPermissionRequest,
        action: SafeguardsActionType,
        tier: SafeguardsTier
    ) async -> SafeguardsDecision {
        guard let outcome = await approvalPrompt.present(request, action: action, tier: tier) else {
            return SafeguardsDecision(outcome: .denied, action: action, classification: .tier(tier), actor: .talos)
        }
        return SafeguardsDecision(outcome: outcome, action: action, classification: .tier(tier), actor: .user)
    }
}
