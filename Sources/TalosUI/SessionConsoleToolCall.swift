import TalosAdapters
import TalosCore
import TalosSafeguards

/// A tool call rendered inline in the transcript, as the agent announced it —
/// "Tool calls as the agent makes them" — carrying whatever the Safeguards
/// gate later decided about it, if anything did.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
public struct SessionConsoleToolCall: Equatable, Sendable {
    /// The originating ``AgentToolCall/id``, so a later ``present(_:action:tier:)``
    /// carrying the correlated ``AgentPermissionRequest`` can find this row
    /// again — the same id an adapter reuses when it holds the call it just
    /// announced.
    public let callID: String
    public let name: String
    public let targets: [String]
    public var approval: SessionConsoleToolCallApproval

    public init(
        callID: String,
        name: String,
        targets: [String],
        approval: SessionConsoleToolCallApproval = .notGated
    ) {
        self.callID = callID
        self.name = name
        self.targets = targets
        self.approval = approval
    }
}

/// What the Safeguards gate has decided about a tool call, if anything.
///
/// ``notGated`` is never assigned by classifying the call's own name — core
/// never switches on that string. It is the structural default every tool
/// call starts at, and it is what a read-tier call keeps forever, since a
/// read-tier action never reaches the gate as a held request at all: "read
/// tier... never prompts."
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#tiers
public enum SessionConsoleToolCallApproval: Equatable, Sendable {
    /// No correlated ``AgentPermissionRequest`` has arrived — read tier, or
    /// not yet held.
    case notGated
    /// The gate is asking the user, with the tier and action it classified —
    /// the data ``SafeguardsApprovalPrompt/present(_:action:tier:)`` receives
    /// and nothing else in the console has.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy
    case pending(request: AgentPermissionRequest, action: SafeguardsActionType, tier: SafeguardsTier)
    /// The user (or the gate, fail-closed) decided. Denied and approved calls
    /// "remain visible in the transcript with their outcome" rather than
    /// disappearing once resolved.
    case resolved(action: SafeguardsActionType, tier: SafeguardsTier, outcome: AgentPermissionDecision)
}
