import TalosAdapters
import TalosCore
import TalosProjectLibrary

/// Maps an adapter-identified verb onto the classifier's own — a translation
/// rather than a shared type, since ``AgentConnectorVerb`` lives in
/// `TalosAdapters`, which does not depend on `TalosSafeguards`.
private extension AgentConnectorVerb {
    var safeguardsVerb: SafeguardsConnectorVerb {
        switch self {
        case .read: .read
        case .write: .write
        }
    }
}

/// The gate's own decision logic: classify, then settle the outcome per
/// [tier](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#tiers)
/// without ever widening one.
///
/// - Refused resolves immediately, actor Talos, and never reaches
///   `approvalPrompt` — an approval path is exactly what a refused type must
///   never have.
///   https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#refused--not-a-tier
/// - Write tier checks `allowlist` first; a hit resolves without a prompt,
///   actor `.allowlist` — an allowlisted pass is still a gated decision,
///   decided by the allowlist rather than asked of the user.
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
/// The action type comes from `request.connectorAccess` when the adapter
/// identified one — resolved against `connectors.yaml` here, at decision time,
/// per call — else from `request.classifiedAction`, the taxonomy type the
/// adapter classified its own tool call as
/// ([decision 96](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions)),
/// else from `request.toolName` read directly as a taxonomy name. A provider
/// tool name is not a taxonomy name, so a call the adapter did not classify
/// falls to irreversible, which is the classifier's designed-for safe default,
/// not a defect of this gate.
///
/// Takes no guideline, intent, or session-instruction text as input, so
/// nothing carried in a prompt or a guideline can reach this decision at
/// all — the structural form of "the gate cannot be disabled by config,
/// guideline, or session instruction."
public struct TieredSafeguardsGate: SafeguardsGate {
    private let allowlist: any SafeguardsAllowlist
    private let approvalPrompt: any SafeguardsApprovalPrompt
    private let connectors: ConnectorsManifest

    public init(
        allowlist: any SafeguardsAllowlist,
        approvalPrompt: any SafeguardsApprovalPrompt,
        connectors: ConnectorsManifest = ConnectorsManifest()
    ) {
        self.allowlist = allowlist
        self.approvalPrompt = approvalPrompt
        self.connectors = connectors
    }

    public func decide(
        _ request: AgentPermissionRequest,
        project: ProjectIdentifier,
        subFunction _: SubFunction
    ) async -> SafeguardsDecision {
        let action = resolvedAction(for: request)
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
                    actor: .allowlist
                )
            }
            return await decideByPrompting(request, action: action, tier: .write)
        case .tier(.irreversible):
            return await decideByPrompting(request, action: action, tier: .irreversible)
        }
    }

    /// Resolves the connector access `denyUnaskable`'s default cannot — it has
    /// no `connectors` — then fails closed at the tier the call would have
    /// prompted at.
    public func denyUnaskable(
        _ request: AgentPermissionRequest,
        project _: ProjectIdentifier,
        subFunction _: SubFunction
    ) async -> SafeguardsDecision {
        let action = resolvedAction(for: request)
        return SafeguardsDecision(
            outcome: .denied,
            action: action,
            classification: SafeguardsActionClassifier.classify(action),
            actor: .talos
        )
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

    /// A connector access is resolved first and against `connectors.isDeclared`
    /// here, live — declared-ness can change and is checked each time, never
    /// cached onto the call — so a `classifiedAction` can never lower the
    /// never-allowlistable undeclared path. Otherwise the adapter's own taxonomy
    /// classification is used
    /// ([decision 96](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions)),
    /// and only a call the adapter did not classify falls back to reading
    /// `toolName` as a taxonomy name — a provider tool name that is not one
    /// classifies as the most-restrictive tier, the classifier's safe default.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable
    private func resolvedAction(for request: AgentPermissionRequest) -> SafeguardsActionType {
        if let access = request.connectorAccess {
            if access.isRepoRemote {
                return resolvedRepoRemoteAction(for: request, access: access)
            }
            return .connector(verb: access.verb.safeguardsVerb, declared: connectors.isDeclared(access.target))
        }
        if let classified = request.classifiedAction {
            return classified
        }
        return SafeguardsActionType(rawValue: request.toolName ?? "")
    }

    /// A git operation reaching a repo remote: its specific taxonomy type when
    /// the repo is declared, `connector.undeclared` when it is not — the same
    /// rule that keeps the undeclared path never-allowlistable, so the adapter's
    /// `git.push` can never lower a push to an undeclared remote below the top
    /// tier. Declared-ness is checked live: an explicit URL against a declared
    /// repo target, a bare remote against whether any repo connector is
    /// declared.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable
    private func resolvedRepoRemoteAction(
        for request: AgentPermissionRequest,
        access: AgentConnectorAccess
    ) -> SafeguardsActionType {
        let declared = access.target.isEmpty
            ? connectors.declaresRepo()
            : connectors.declaresTarget(access.target)
        guard declared, let classified = request.classifiedAction else {
            return .connectorUndeclared
        }
        return classified
    }
}
