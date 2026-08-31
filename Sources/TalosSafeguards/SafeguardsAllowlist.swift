import TalosCore
import TalosProjectLibrary

/// Whether a write-tier action is pre-approved for a project, so the gate can
/// pass it without a prompt. Allowlists are **per project, per action type**
/// — never global — and matching is exact string equality, never a prefix.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#naming-and-matching
///
/// Declared here with no conformance in this module: the allowlist store —
/// where entries live in `.talos/` and how they are edited — is tracked
/// separately. The gate only needs the yes/no answer.
///
/// Never consulted for an irreversible-tier action: that tier is "not
/// allowlistable, ever," so the gate does not call this for one, regardless
/// of what a conformance would answer.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#tiers
public protocol SafeguardsAllowlist: Sendable {
    func isAllowlisted(_ action: SafeguardsActionType, project: ProjectIdentifier) async -> Bool
}
