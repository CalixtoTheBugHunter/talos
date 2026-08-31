import TalosAdapters
import TalosCore
import TalosProjectLibrary

/// One row of the gated-decision log: "Every gated decision is **logged** with
/// the actor, the action, the tier, and the outcome."
///
/// The request's own id and wording travel with those four so a row names what
/// the agent asked for in the words the user was shown, rather than a category
/// a reader has to map back to an action.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
public struct GatedDecisionEntry: Equatable, Sendable {
    public let project: ProjectIdentifier
    public let subFunction: SubFunction
    public let requestID: AgentPermissionRequest.ID
    public let requestPrompt: String
    public let action: SafeguardsActionType
    public let tier: SafeguardsTier
    public let actor: SafeguardsDecisionActor
    public let outcome: AgentPermissionDecision

    /// Takes the request and the decision whole, so no caller can pair an
    /// outcome with another request's fields.
    public init(
        project: ProjectIdentifier,
        subFunction: SubFunction,
        request: AgentPermissionRequest,
        decision: SafeguardsDecision
    ) {
        self.project = project
        self.subFunction = subFunction
        requestID = request.id
        requestPrompt = request.prompt
        action = decision.action
        tier = decision.tier
        actor = decision.actor
        outcome = decision.outcome
    }
}

/// Where every gated decision is written, one entry per decision.
///
/// Non-throwing for the reason the session record writer is: a write that
/// could fail and be swallowed leaves a decision unlogged, and this log is the
/// only record of what an agent was allowed or refused. Retry and durability
/// belong to the implementation.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
public protocol GatedDecisionLog: Sendable {
    func record(_ entry: GatedDecisionEntry) async
}
