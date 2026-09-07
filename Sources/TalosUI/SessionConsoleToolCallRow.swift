import SwiftUI
import TalosAdapters
import TalosSafeguards

/// One tool-call row in the transcript: the call as the agent announced it,
/// plus whatever the Safeguards gate has decided about it so far.
///
/// This is the surface the SPEC means by "approval prompts inline, where the
/// work is happening" — the pending case embeds the same
/// ``SafeguardsApprovalPromptView`` a sheet would have shown, as a row in the
/// transcript rather than a detached modal.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
struct SessionConsoleToolCallRow: View {
    let call: SessionConsoleToolCall
    let onDecide: (AgentPermissionDecision) -> Void

    var body: some View {
        switch call.approval {
        case .notGated:
            readTierRow
        case let .pending(request, action, tier):
            SafeguardsApprovalPromptView(
                request: request,
                action: action,
                tier: tier,
                onApprove: { onDecide(.allowed) },
                onDeny: { onDecide(.denied) }
            )
        case let .resolved(_, tier, outcome):
            resolvedRow(tier: tier, outcome: outcome)
        }
    }

    /// De-emphasized, but never by color alone: this row carries no tier or
    /// outcome caption at all, and that absence — not a hue — is what
    /// distinguishes it from a pending or resolved one. It carries no tier
    /// label because core is never told one for a call that never reached
    /// the gate: "the tool name is not an action type", so this row does not
    /// guess "Read" from ``SessionConsoleToolCall/name``.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#tiers
    private var readTierRow: some View {
        HStack(alignment: .top) {
            Image(systemName: "arrow.right.circle")
                .accessibilityHidden(true)
            Text(verbatim: summary)
                .textSelection(.enabled)
        }
        .foregroundStyle(.secondary)
        .padding(.vertical)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: summary))
    }

    /// Denied and approved calls "remain visible in the transcript with
    /// their outcome" — never by color alone: an SF Symbol distinct per
    /// outcome, plus a text label, the same split
    /// ``GatedDecisionLogRow``'s own outcome symbol uses.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#never-by-color-alone
    private func resolvedRow(tier: SafeguardsTier, outcome: AgentPermissionDecision) -> some View {
        HStack(alignment: .top) {
            Image(systemName: outcomeSymbol(outcome))
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(verbatim: summary)
                    .textSelection(.enabled)
                Text(verbatim: "\(tierLabel(tier)) · \(outcomeLabel(outcome))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(outcomeLabel(outcome)). \(summary). \(tierLabel(tier))."))
    }

    private var summary: String {
        call.targets.isEmpty ? call.name : "\(call.name) \(call.targets.joined(separator: ", "))"
    }

    private func outcomeSymbol(_ outcome: AgentPermissionDecision) -> String {
        switch outcome {
        case .allowed: "checkmark.circle"
        case .denied: "hand.raised"
        }
    }

    private func tierLabel(_ tier: SafeguardsTier) -> String {
        switch tier {
        case .read: "Read"
        case .write: "Write"
        case .irreversible: "Irreversible"
        }
    }

    private func outcomeLabel(_ outcome: AgentPermissionDecision) -> String {
        switch outcome {
        case .allowed: "Allowed"
        case .denied: "Denied"
        }
    }
}
