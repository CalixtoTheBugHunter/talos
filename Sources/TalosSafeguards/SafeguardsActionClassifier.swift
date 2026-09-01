import TalosCore

/// What classifying an action type resolves to: a tier, or an outright
/// refusal.
///
/// Two cases rather than folding refusal into `SafeguardsTier`, because a
/// refused type is not a tier — no approval path can open it, which a fourth
/// `SafeguardsTier` case would leave a caller free to try anyway.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#refused--not-a-tier
public enum SafeguardsClassification: Equatable, Hashable, Sendable {
    case tier(SafeguardsTier)
    case refused
}

/// Maps a `taxonomy: 1` action type onto its classification. See
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy
///
/// Pure and stateless — no I/O, so every one of the taxonomy's entries is
/// exhaustively testable, and an unrecognized name is a lookup miss rather
/// than a thrown error.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#action-classification
public enum SafeguardsActionClassifier {
    /// > Classification defaults to the most restrictive tier when a call is
    /// > unrecognized — never to read.
    ///
    /// So a name absent from both tables below returns `.tier(.irreversible)`
    /// rather than `nil` or a thrown error: the taxonomy's job is to *narrow*
    /// what gates in the moment, never to be a precondition of being gated
    /// at all.
    public static func classify(_ actionType: SafeguardsActionType) -> SafeguardsClassification {
        if refused.contains(actionType) {
            return .refused
        }
        return .tier(tiers[actionType] ?? .irreversible)
    }

    /// Every name `taxonomy: 1` actually declares — the 3 refused plus the 43
    /// tiered entries — distinct from what `classify` returns for a name
    /// outside that set. `classify` must default an unknown name to
    /// irreversible so the *gate* never falls through to read; a store
    /// validating what a user may write into an allowlist needs the sharper
    /// question this answers instead: is this name in the taxonomy at all.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy
    public static var knownActionTypes: Set<SafeguardsActionType> {
        refused.union(tiers.keys)
    }

    /// The three refused types. See
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#refused--not-a-tier
    ///
    /// Checked ahead of the tier table so a name that is both refused and
    /// (hypothetically) tiered never resolves to the weaker outcome.
    private static let refused: Set<SafeguardsActionType> = [
        .configSafeguardsWrite,
        .configAllowlistWrite,
        .configTierWrite
    ]

    /// The 43 tiered entries, exactly as
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy
    /// tables them — 8 read, 15 write, 20 irreversible.
    private static let tiers: [SafeguardsActionType: SafeguardsTier] = [
        // Read.
        .fileRead: .read,
        .fileSearch: .read,
        .gitRead: .read,
        .boardRead: .read,
        .specRead: .read,
        .configRead: .read,
        .connectorRead: .read,
        .analysisLocal: .read,

        // Write.
        .fileWrite: .write,
        .fileMove: .write,
        .gitCommit: .write,
        .gitBranchCreate: .write,
        .gitPush: .write,
        .gitPROpen: .write,
        .gitPRComment: .write,
        .boardItemCreate: .write,
        .boardItemMove: .write,
        .boardItemUpdate: .write,
        .boardItemComment: .write,
        .specWrite: .write,
        .configWrite: .write,
        .configGuidelinesWrite: .write,
        .connectorWrite: .write,

        // Irreversible / outward-facing.
        .processRun: .irreversible,
        .fileDelete: .irreversible,
        .gitPushProtected: .irreversible,
        .gitPushForce: .irreversible,
        .gitHistoryRewrite: .irreversible,
        .gitBranchDelete: .irreversible,
        .gitRepoDelete: .irreversible,
        .gitPRMerge: .irreversible,
        .boardItemDelete: .irreversible,
        .specDelete: .irreversible,
        .specDriveCreate: .irreversible,
        .secretRead: .irreversible,
        .secretWrite: .irreversible,
        .secretSend: .irreversible,
        .deployStaging: .irreversible,
        .deployProduction: .irreversible,
        .packageInstall: .irreversible,
        .packagePublish: .irreversible,
        .spendPaid: .irreversible,
        .connectorUndeclared: .irreversible
    ]
}

/// Which side of a connector action was requested, before target
/// declaration is weighed in. Not an action type itself — see
/// ``SafeguardsActionType/connector(verb:declared:)``.
public enum SafeguardsConnectorVerb: Sendable {
    case read
    case write
}

public extension SafeguardsActionType {
    /// Resolves a connector action's type from its verb and whether the
    /// target is declared in `connectors.yaml`.
    ///
    /// > `connector.undeclared` is classified by its **target, not its
    /// > verb**, so it overrides whatever the verb would have given.
    ///
    /// So an undeclared target always wins, regardless of `verb` — a read
    /// against an undeclared system is `connector.undeclared`, never
    /// `connector.read`.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy
    static func connector(verb: SafeguardsConnectorVerb, declared: Bool) -> SafeguardsActionType {
        guard declared else {
            return .connectorUndeclared
        }
        switch verb {
        case .read:
            return .connectorRead
        case .write:
            return .connectorWrite
        }
    }
}
