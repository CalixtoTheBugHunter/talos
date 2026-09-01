import TalosCore

/// The exact `taxonomy: 1` names carrying one of the eight SPEC items no
/// configuration, preference, or agent request may move out of in-the-moment
/// approval — the 🔒 set.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable
///
/// A compiled-in `Set` literal, not a value read from `.talos/` or anywhere
/// else on disk — there is no configuration surface that can add to, remove
/// from, or shrink it. That is what makes "ever" mean ever: nothing at
/// runtime can shrink a set that was never a variable to begin with.
///
/// Eleven names for eight SPEC items because two of them split across
/// several taxonomy entries: "Branch or repo deletion" is two types, and
/// "Secret access or exfiltration" is three. See
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#irreversible--outward-facing
///
/// This registry names the eight items on their own terms, for the fix
/// message ``AllowlistStore`` quotes when one of them is attempted. It does
/// not replace the tier check that actually rejects a write: every
/// irreversible-tier type is unallowlistable because
/// ``SafeguardsActionClassifier`` classifies it that way — this registry
/// marks what the SPEC names by hand within that tier, not a second gate.
public enum SafeguardsNeverAllowlistable {
    /// > No configuration, no user preference, and no agent request can move
    /// > these out of in-the-moment approval.
    public static let registry: Set<SafeguardsActionType> = [
        // Force-push.
        .gitPushForce,
        // History rewrite.
        .gitHistoryRewrite,
        // Branch or repo deletion.
        .gitBranchDelete,
        .gitRepoDelete,
        // Secret access or exfiltration.
        .secretRead,
        .secretWrite,
        .secretSend,
        // Production deploys.
        .deployProduction,
        // Paid-service spend.
        .spendPaid,
        // Package publishing.
        .packagePublish,
        // Any action against a system not declared in connectors.yaml.
        .connectorUndeclared
    ]
}
