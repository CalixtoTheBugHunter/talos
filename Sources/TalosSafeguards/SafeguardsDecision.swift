import TalosAdapters

/// Which tier the gate classified an action into.
///
/// Three cases because the tier table has three rows. What picks one — the
/// versioned taxonomy, per-project allowlisting — is tracked separately; this
/// type exists so the chosen tier can cross the gate's boundary as a value,
/// since the audit log is required to name it.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#tiers
public enum SafeguardsTier: String, Equatable, Hashable, Sendable {
    case read
    case write
    case irreversible
}

/// One action type from the taxonomy, as the name a user writes into `.talos/`.
///
/// A wrapper over a string rather than an enum: an action type "is not an
/// internal enum — it is a **name a user has written into `.talos/` and
/// expects to keep meaning what it meant**", and the set itself is versioned
/// and owned by the classifier.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy
public struct SafeguardsActionType: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Who a decision is attributed to.
///
/// Talos is an actor in its own right because a fail-closed denial is Talos's
/// act, not the user's: "a log that shows a user denial they never made is a
/// wrong record rather than a cautious one."
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed
public enum SafeguardsDecisionActor: String, Equatable, Hashable, Sendable {
    /// The user answered the prompt.
    case user
    /// Talos answered without the user deciding — a fail-closed denial, or an
    /// outcome the tier settles with no prompt at all.
    case talos
}

/// What the gate decided, carrying the four fields a gated decision is logged
/// with.
///
/// All four are returned together because the gate is the only party that
/// knows them: the session pipeline hands `outcome` back to the adapter and
/// writes the whole value to the log, and it cannot reconstruct a tier or an
/// actor it was never told.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
public struct SafeguardsDecision: Equatable, Hashable, Sendable {
    public let outcome: AgentPermissionDecision
    public let action: SafeguardsActionType
    public let tier: SafeguardsTier
    public let actor: SafeguardsDecisionActor

    public init(
        outcome: AgentPermissionDecision,
        action: SafeguardsActionType,
        tier: SafeguardsTier,
        actor: SafeguardsDecisionActor
    ) {
        self.outcome = outcome
        self.action = action
        self.tier = tier
        self.actor = actor
    }
}
