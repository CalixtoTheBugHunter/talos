import TalosAdapters
import TalosCore

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
/// writes the whole value to the log, and it cannot reconstruct a
/// classification or an actor it was never told.
///
/// Carries `SafeguardsClassification` rather than a bare `SafeguardsTier` so a
/// refused decision can be logged as refused rather than as a denial at some
/// tier — "refused is not a tier", and a log that cannot say so has recorded
/// a generic denial where the SPEC wants the specific refusal.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#refused--not-a-tier
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
public struct SafeguardsDecision: Equatable, Hashable, Sendable {
    public let outcome: AgentPermissionDecision
    public let action: SafeguardsActionType
    public let classification: SafeguardsClassification
    public let actor: SafeguardsDecisionActor

    public init(
        outcome: AgentPermissionDecision,
        action: SafeguardsActionType,
        classification: SafeguardsClassification,
        actor: SafeguardsDecisionActor
    ) {
        self.outcome = outcome
        self.action = action
        self.classification = classification
        self.actor = actor
    }
}
