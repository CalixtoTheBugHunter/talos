import TalosAdapters
import TalosCore
import TalosSafeguards

/// One tool call's identity for retry detection — the tool it named and the
/// targets it stated, exactly as the agent stated them. Two calls with this
/// pair equal are "the same action" for
/// ``SessionRunMetrics/retryCount``'s purposes.
struct ToolCallSignature: Hashable, Sendable {
    let name: String
    let targets: [String]
}

/// Tracks which tool-call signatures have been denied this session, so a
/// later `.toolCall` repeating one can be counted as a retry and a later
/// `.permissionRequest` repeating one can be blocked without asking again.
/// Two calls contribute to this: `noteToolCall` remembers a call's own
/// signature by its id, and `noteDenial` — given the id and decision a
/// `.permissionRequest` denial answers — promotes that remembered signature
/// into the denied set, carrying the decision's own action and
/// classification so a later block can log honestly without re-classifying.
struct RetryTracker {
    private var signaturesByCallID: [String: ToolCallSignature] = [:]
    private var deniedSignatures: [ToolCallSignature: SafeguardsDecision] = [:]

    /// Records `call`'s signature and reports whether it repeats one already
    /// denied this session.
    mutating func noteToolCall(_ call: AgentToolCall) -> Bool {
        let signature = ToolCallSignature(name: call.name, targets: call.targets)
        signaturesByCallID[call.id] = signature
        return deniedSignatures.keys.contains(signature)
    }

    /// The permission request `requestID` was denied by `action`/`classification`.
    /// If it correlates to an observed `.toolCall` (the adapter contract does
    /// not guarantee one does), that call's signature is now a denied one.
    mutating func noteDenial(
        of requestID: String,
        action: SafeguardsActionType,
        classification: SafeguardsClassification
    ) {
        guard let signature = signaturesByCallID[requestID] else { return }
        deniedSignatures[signature] = SafeguardsDecision(
            outcome: .denied,
            action: action,
            classification: classification,
            actor: .talos
        )
    }

    /// A synthesized denial for `requestID`, if it correlates to a `.toolCall`
    /// signature already denied this session — the gate is not consulted for
    /// this decision, so the user is never asked about the same action twice.
    func blockedDecision(for requestID: String) -> SafeguardsDecision? {
        guard let signature = signaturesByCallID[requestID] else { return nil }
        return deniedSignatures[signature]
    }
}
