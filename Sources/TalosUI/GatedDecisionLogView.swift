import SwiftUI
import TalosAdapters
import TalosOrchestration
import TalosSafeguards

/// Renders a ``GatedDecisionLogViewModel``'s state as a list of gated
/// decisions — "every gated decision is logged with the actor, the action,
/// the tier, and the outcome", made visible to the user rather than only in
/// a file.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
@MainActor
public struct GatedDecisionLogView: View {
    private let state: GatedDecisionLogViewModel.State
    private let onRetry: () -> Void

    @State private var selection: Int?

    public init(state: GatedDecisionLogViewModel.State, onRetry: @escaping () -> Void) {
        self.state = state
        self.onRetry = onRetry
    }

    public var body: some View {
        switch state {
        case .loading:
            ProgressView()
                .accessibilityLabel(Text(verbatim: "Loading the decision log"))
                .padding()
        case .empty:
            Text(verbatim: "No gated decisions yet.")
                .foregroundStyle(.secondary)
                .padding()
                .accessibilityLabel(Text(verbatim: "No gated decisions yet"))
        case let .ready(entries):
            List(entries, selection: $selection) { entry in
                GatedDecisionLogRow(entry: entry)
            }
        case let .failed(message):
            VStack {
                Text(verbatim: message)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onRetry) {
                    Text(verbatim: "Retry")
                }
                .accessibilityHint(Text(verbatim: "Reads the decision log again."))
            }
            .padding()
        }
    }
}

/// One row: actor, action, tier or "Refused", outcome, and when — never
/// distinguished by color alone.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#never-by-color-alone
private struct GatedDecisionLogRow: View {
    let entry: StoredGatedDecisionEntry

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: outcomeSymbol)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(verbatim: entry.requestPrompt.isEmpty ? entry.action.rawValue : entry.requestPrompt)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: "\(actorLabel) · \(entry.action.rawValue) · \(tierLabel) · \(outcomeLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(entry.timestamp, format: .dateTime)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical)
        .focusable()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: accessibilitySentence))
    }

    private var outcomeSymbol: String {
        switch entry.outcome {
        case .allowed: "checkmark.circle"
        case .denied: "hand.raised"
        }
    }

    private var actorLabel: String {
        switch entry.actor {
        case .user: "User"
        case .talos: "Talos"
        case .allowlist: "Allowlist"
        }
    }

    private var tierLabel: String {
        switch entry.classification {
        case .refused: "Refused"
        case let .tier(tier):
            switch tier {
            case .read: "Read"
            case .write: "Write"
            case .irreversible: "Irreversible"
            }
        }
    }

    private var outcomeLabel: String {
        switch entry.outcome {
        case .allowed: "Allowed"
        case .denied: "Denied"
        }
    }

    private var accessibilitySentence: String {
        let target = entry.requestPrompt.isEmpty ? entry.action.rawValue : entry.requestPrompt
        let when = entry.timestamp.formatted(date: .abbreviated, time: .standard)
        let detail = "Actor \(actorLabel), action \(entry.action.rawValue), tier \(tierLabel)."
        return "\(outcomeLabel). \(target). \(detail) \(when)."
    }
}
