import TalosCore
import TalosSafeguards

/// The copy an approval prompt shows for a gated action.
///
/// Never invents target detail Talos does not have — a request's own
/// wording, shown verbatim, carries the operation and the target. This type
/// supplies only what Talos itself knows from the action and its tier: a
/// label naming the action for the approve control, and whether the tier can
/// be undone.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice#approval-copy
public enum SafeguardsApprovalCopy {
    /// The approve control's label, naming the action rather than a bare
    /// "OK" — paraphrased from what the taxonomy already says each type
    /// covers. Falls back to an honest generic phrase for a name outside the
    /// taxonomy, rather than guessing a specific one Talos cannot back up.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy
    public static func operationLabel(for action: SafeguardsActionType) -> String {
        labels[action] ?? "Approve this action"
    }

    /// Reversibility is a property of the tier itself — the irreversible
    /// tier is named for it, the write tier is not — so this needs no
    /// per-action table.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#tiers
    public static func reversibilityStatement(for tier: SafeguardsTier) -> String {
        tier == .irreversible ? "This cannot be undone." : "This can be undone."
    }

    private static let labels: [SafeguardsActionType: String] = [
        // Write tier.
        .fileWrite: "Create or modify a file",
        .fileMove: "Rename or relocate a file",
        .gitCommit: "Commit to a local branch",
        .gitBranchCreate: "Create a branch",
        .gitPush: "Push to an unprotected branch",
        .gitPROpen: "Open a pull request",
        .gitPRComment: "Comment on a pull request",
        .boardItemCreate: "Create a board item",
        .boardItemMove: "Move a board item",
        .boardItemUpdate: "Edit a board item",
        .boardItemComment: "Comment on a board item",
        .specWrite: "Edit the Spec Drive",
        .configWrite: "Write to .talos/",
        .configGuidelinesWrite: "Edit a Talos guideline",
        .connectorWrite: "Write to a connected system",

        // Irreversible / outward-facing tier.
        .processRun: "Run a command",
        .fileDelete: "Delete a file or directory",
        .gitPushProtected: "Push to a protected branch",
        .gitPushForce: "Force-push",
        .gitHistoryRewrite: "Rewrite git history",
        .gitBranchDelete: "Delete a branch",
        .gitRepoDelete: "Delete the repository",
        .gitPRMerge: "Merge a pull request",
        .boardItemDelete: "Delete a board item",
        .specDelete: "Delete Spec Drive content",
        .specDriveCreate: "Create a Spec Drive",
        .secretRead: "Read a secret",
        .secretWrite: "Write or rotate a secret",
        .secretSend: "Send a secret outside the Keychain",
        .deployStaging: "Deploy to staging",
        .deployProduction: "Deploy to production",
        .packageInstall: "Install a dependency",
        .packagePublish: "Publish a package",
        .spendPaid: "Spend money",
        .connectorUndeclared: "Act against an undeclared system"
    ]
}
