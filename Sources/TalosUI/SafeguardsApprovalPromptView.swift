import SwiftUI
import TalosAdapters
import TalosCore
import TalosSafeguards

/// The approval prompt itself — one pending request, presented as the
/// sentence first and the controls after, in reading order and focus order
/// alike, with nothing armed on arrival. See § The form of an approval prompt.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard
@MainActor
public struct SafeguardsApprovalPromptView: View {
    private enum Control {
        case deny
        case approve
    }

    private let request: AgentPermissionRequest
    private let action: SafeguardsActionType
    private let tier: SafeguardsTier
    private let onApprove: () -> Void
    private let onDeny: () -> Void

    @FocusState private var focusedControl: Control?

    public init(
        request: AgentPermissionRequest,
        action: SafeguardsActionType,
        tier: SafeguardsTier,
        onApprove: @escaping () -> Void,
        onDeny: @escaping () -> Void
    ) {
        self.request = request
        self.action = action
        self.tier = tier
        self.onApprove = onApprove
        self.onDeny = onDeny
    }

    public var body: some View {
        VStack(alignment: .leading) {
            Text(verbatim: sentence)

            Text(verbatim: "\(tierLabel) · \(SafeguardsApprovalCopy.reversibilityStatement(for: tier))")
                .foregroundStyle(.secondary)

            HStack {
                denyButton
                Spacer()
                approveButton
            }
        }
        .padding()
        .onAppear {
            focusedControl = .deny
        }
    }

    private var denyButton: some View {
        Button(role: .cancel, action: onDeny) {
            Text(verbatim: "Deny")
        }
        .keyboardShortcut(.cancelAction)
        .focused($focusedControl, equals: .deny)
        .accessibilityHint(Text(verbatim: "Denies the action above. The session stays open."))
    }

    @ViewBuilder
    private var approveButton: some View {
        let plain = Button(action: onApprove) {
            Text(verbatim: SafeguardsApprovalCopy.operationLabel(for: action))
        }
        .buttonStyle(.borderedProminent)
        .focused($focusedControl, equals: .approve)
        .accessibilityHint(Text(verbatim: approveHint))

        // No shortcut at all when irreversible — `↩` is unbound here on
        // every tier but write, with no exception to add later. See
        // § Return never approves an irreversible action.
        // https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard
        switch tier {
        case .write:
            plain.keyboardShortcut(KeyboardShortcut(.return, modifiers: .command))
        case .read, .irreversible:
            plain
        }
    }

    private var sentence: String {
        request.prompt.isEmpty ? SafeguardsApprovalCopy.operationLabel(for: action) : request.prompt
    }

    /// Named so the user can see why the action prompted at all — "the tier
    /// of each tool call is visible" — rather than inferring it only from the
    /// reversibility statement it is now paired with.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#tiers
    private var tierLabel: String {
        switch tier {
        case .read: "Read"
        case .write: "Write"
        case .irreversible: "Irreversible"
        }
    }

    private var approveHint: String {
        let reversibility = SafeguardsApprovalCopy.reversibilityStatement(for: tier)
        switch tier {
        case .irreversible:
            return "\(reversibility) No keyboard shortcut approves this action."
        case .write, .read:
            return "\(reversibility) Command-Return approves."
        }
    }
}
