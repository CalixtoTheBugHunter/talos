/// One action type from the taxonomy, as the name a user writes into `.talos/`.
///
/// A wrapper over a string rather than an enum: an action type "is not an
/// internal enum — it is a **name a user has written into `.talos/` and
/// expects to keep meaning what it meant**", and the set itself is versioned
/// and owned by the classifier.
///
/// Lives in `TalosCore` — not `TalosSafeguards`, which depends on
/// `TalosAdapters` — so an adapter can map the tool name it detected onto
/// this value without inverting the module graph.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy
public struct SafeguardsActionType: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// `taxonomy: 1`, spelled exactly as the taxonomy table spells it — lowercase,
/// dotted `domain.verb`. Matching is exact string equality, never a prefix,
/// so a constant here is the only spelling of its name Talos ever produces.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy
public extension SafeguardsActionType {
    // MARK: Read tier

    /// Read a file in the project.
    static let fileRead = SafeguardsActionType(rawValue: "file.read")
    /// Search the project's contents.
    static let fileSearch = SafeguardsActionType(rawValue: "file.search")
    /// Status, log, diff, blame — anything that mutates nothing.
    static let gitRead = SafeguardsActionType(rawValue: "git.read")
    /// Read board items and their state.
    static let boardRead = SafeguardsActionType(rawValue: "board.read")
    /// Read the Spec Drive.
    static let specRead = SafeguardsActionType(rawValue: "spec.read")
    /// Read `.talos/`.
    static let configRead = SafeguardsActionType(rawValue: "config.read")
    /// Read from a declared system — logs, monitoring, CI status.
    static let connectorRead = SafeguardsActionType(rawValue: "connector.read")
    /// Analysis Talos performs over content it already holds.
    static let analysisLocal = SafeguardsActionType(rawValue: "analysis.local")

    // MARK: Write tier

    /// Create or modify a file.
    static let fileWrite = SafeguardsActionType(rawValue: "file.write")
    /// Rename or relocate a file.
    static let fileMove = SafeguardsActionType(rawValue: "file.move")
    /// Commit to a local branch.
    static let gitCommit = SafeguardsActionType(rawValue: "git.commit")
    /// Create a branch.
    static let gitBranchCreate = SafeguardsActionType(rawValue: "git.branch.create")
    /// Push to an unprotected branch on a declared remote.
    static let gitPush = SafeguardsActionType(rawValue: "git.push")
    /// Open a pull request.
    static let gitPROpen = SafeguardsActionType(rawValue: "git.pr.open")
    /// Comment or leave a review on a pull request.
    static let gitPRComment = SafeguardsActionType(rawValue: "git.pr.comment")
    /// Create a board item.
    static let boardItemCreate = SafeguardsActionType(rawValue: "board.item.create")
    /// Move an item between states.
    static let boardItemMove = SafeguardsActionType(rawValue: "board.item.move")
    /// Edit an item's fields.
    static let boardItemUpdate = SafeguardsActionType(rawValue: "board.item.update")
    /// Comment on a board item.
    static let boardItemComment = SafeguardsActionType(rawValue: "board.item.comment")
    /// Edit the Spec Drive.
    static let specWrite = SafeguardsActionType(rawValue: "spec.write")
    /// Write `.talos/`, other than the three refused types below.
    static let configWrite = SafeguardsActionType(rawValue: "config.write")
    /// Write an Editable Talos Guideline.
    static let configGuidelinesWrite = SafeguardsActionType(rawValue: "config.guidelines.write")
    /// A write to a declared system with no more specific type.
    static let connectorWrite = SafeguardsActionType(rawValue: "connector.write")

    // MARK: Irreversible / outward-facing tier

    /// Execute a command — it cannot be proven safe before it runs.
    static let processRun = SafeguardsActionType(rawValue: "process.run")
    /// Delete a file or directory.
    static let fileDelete = SafeguardsActionType(rawValue: "file.delete")
    /// Push to a protected branch.
    static let gitPushProtected = SafeguardsActionType(rawValue: "git.push.protected")
    /// Force-push.
    static let gitPushForce = SafeguardsActionType(rawValue: "git.push.force")
    /// Rewrite history — rebase, amend, or filter a pushed branch.
    static let gitHistoryRewrite = SafeguardsActionType(rawValue: "git.history.rewrite")
    /// Delete a branch.
    static let gitBranchDelete = SafeguardsActionType(rawValue: "git.branch.delete")
    /// Delete a repository.
    static let gitRepoDelete = SafeguardsActionType(rawValue: "git.repo.delete")
    /// Merge a pull request.
    static let gitPRMerge = SafeguardsActionType(rawValue: "git.pr.merge")
    /// Delete a board item.
    static let boardItemDelete = SafeguardsActionType(rawValue: "board.item.delete")
    /// Delete Spec Drive content.
    static let specDelete = SafeguardsActionType(rawValue: "spec.delete")
    /// Create a Spec Drive.
    static let specDriveCreate = SafeguardsActionType(rawValue: "spec.drive.create")
    /// Read a secret.
    static let secretRead = SafeguardsActionType(rawValue: "secret.read")
    /// Write or rotate a secret.
    static let secretWrite = SafeguardsActionType(rawValue: "secret.write")
    /// Pass a secret anywhere outside the Keychain accessor.
    static let secretSend = SafeguardsActionType(rawValue: "secret.send")
    /// Deploy to a non-production environment.
    static let deployStaging = SafeguardsActionType(rawValue: "deploy.staging")
    /// Deploy to production.
    static let deployProduction = SafeguardsActionType(rawValue: "deploy.production")
    /// Install a dependency.
    static let packageInstall = SafeguardsActionType(rawValue: "package.install")
    /// Publish a package.
    static let packagePublish = SafeguardsActionType(rawValue: "package.publish")
    /// Anything that spends money.
    static let spendPaid = SafeguardsActionType(rawValue: "spend.paid")
    /// Any action against a system not declared in `connectors.yaml`.
    static let connectorUndeclared = SafeguardsActionType(rawValue: "connector.undeclared")

    // MARK: Refused — not a tier

    /// Write `.talos/safeguards.md`. Refused outright; see
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#refused--not-a-tier
    static let configSafeguardsWrite = SafeguardsActionType(rawValue: "config.safeguards.write")
    /// Add to, remove from, or reorder an allowlist. Refused outright.
    static let configAllowlistWrite = SafeguardsActionType(rawValue: "config.allowlist.write")
    /// Change any action type's tier. Refused outright.
    static let configTierWrite = SafeguardsActionType(rawValue: "config.tier.write")
}
