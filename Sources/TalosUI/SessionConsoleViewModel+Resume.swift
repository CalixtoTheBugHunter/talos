import TalosAdapters
import TalosOrchestration
import TalosSafeguards

/// Resume and export — split out of `SessionConsoleViewModel.swift` because
/// that file, holding every streaming behaviour plus these two, ran past this
/// module's own file-length limit.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
public extension SessionConsoleViewModel {
    /// Seeds a resumed session's console with its prior transcript, before any
    /// live event from the new run arrives — "a prior session can be resumed
    /// with its transcript and context intact." Each stored
    /// ``SessionTranscriptEntry`` replays through the same
    /// ``appendOutput(_:)``/``handle(_:)`` paths a live stream drives, so the
    /// reconstruction shares this view model's one line-splitting
    /// implementation rather than a second one that could drift from it.
    /// `decisions` — read from the ``GatedDecisionLog``, never duplicated into
    /// a second store — resolves each replayed tool call to what the gate
    /// already decided for it, in the same ``SessionConsoleToolCallApproval/resolved(action:tier:outcome:)``
    /// shape a live approval leaves behind. A `.refused` classification has no
    /// tier of its own to show; it renders at ``SafeguardsTier/irreversible``,
    /// the most restrictive tier this row can carry, never understating it.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
    func preload(_ entries: [SessionTranscriptEntry], decisions: [StoredGatedDecisionEntry]) {
        sessionStarted()
        let decisionsByRequestID = Dictionary(
            decisions.map { ($0.requestID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for entry in entries {
            switch entry {
            case let .output(text):
                appendOutput(AgentOutputChunk(channel: .standardOutput, text: text))
            case let .toolCall(id, name, targets):
                handle(.toolCall(AgentToolCall(id: id, name: name, targets: targets)))
                if let decision = decisionsByRequestID[id] {
                    resolvePreloadedToolCall(id, with: decision)
                }
            }
        }
    }

    /// "Export produces a readable file (Markdown) including tool calls and
    /// approvals." Delegates to ``SessionConsoleTranscriptExporter``, which
    /// re-redacts defensively — this view model's own `lines` may hold live,
    /// unredacted output the storage layer's write-time redaction never saw.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
    func exportMarkdown() -> String {
        SessionConsoleTranscriptExporter.markdown(for: lines)
    }

    /// A `.refused` classification has no tier of its own — it renders at
    /// ``SafeguardsTier/irreversible``, the most restrictive tier this row
    /// can carry, rather than understating it.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#refused--not-a-tier
    private func resolvePreloadedToolCall(_ callID: String, with decision: StoredGatedDecisionEntry) {
        let tier: SafeguardsTier = if case let .tier(tier) = decision.classification {
            tier
        } else {
            .irreversible
        }
        let approval = SessionConsoleToolCallApproval.resolved(
            action: decision.action,
            tier: tier,
            outcome: decision.outcome
        )
        updateToolCall(callID: callID, approval: approval)
    }
}
