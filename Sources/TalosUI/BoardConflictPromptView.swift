import SwiftUI
import TalosOrchestration
import TalosProjectLibrary

/// The board conflict prompt — decision 42's detect-and-ask, shown when an item
/// diverged from the state Talos read. Sentence first, the two states and who
/// changed it, then the three outcomes. `↩` is bound to none of them: the two
/// outcomes are not symmetrical and the safe one is not obvious. `⎋` keeps the
/// board's state, the abandon that overwrites nothing, so the cheapest key is
/// the conservative one.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#when-a-human-and-talos-move-the-same-item
@MainActor
public struct BoardConflictPromptView: View {
    private enum Control {
        case keep
        case open
        case apply
    }

    private let presentation: BoardConflictPresentation
    private let onKeep: () -> Void
    private let onApply: () -> Void
    private let onOpen: () -> Void

    @FocusState private var focusedControl: Control?
    @Environment(\.openURL) private var openURL

    public init(
        presentation: BoardConflictPresentation,
        onKeep: @escaping () -> Void,
        onApply: @escaping () -> Void,
        onOpen: @escaping () -> Void
    ) {
        self.presentation = presentation
        self.onKeep = onKeep
        self.onApply = onApply
        self.onOpen = onOpen
    }

    public var body: some View {
        VStack(alignment: .leading) {
            Text(verbatim: sentence)

            Text(verbatim: stateSentence)
                .foregroundStyle(.secondary)
            Text(verbatim: provenanceSentence)
                .foregroundStyle(.secondary)

            HStack {
                keepButton
                openButton
                Spacer()
                applyButton
            }
        }
        .padding()
        .onAppear {
            // Nothing is armed on arrival: focus rests on the conservative
            // control, and no control is the default `↩` activates.
            focusedControl = .keep
        }
    }

    private var keepButton: some View {
        Button(role: .cancel, action: onKeep) {
            Text(verbatim: "Keep the board's state")
        }
        .keyboardShortcut(.cancelAction)
        .focused($focusedControl, equals: .keep)
        .accessibilityHint(Text(verbatim:
            "Abandons Talos's move. The item keeps its current state and the session continues."))
    }

    private var openButton: some View {
        Button(action: open) {
            Text(verbatim: "Open the item")
        }
        .focused($focusedControl, equals: .open)
        .accessibilityHint(Text(verbatim:
            "Opens the item so you can decide with its full history. Talos's move is abandoned."))
    }

    /// Opens the item's provider page, then abandons the write. When the read
    /// supplied no URL the item cannot be opened, so the outcome is the same
    /// abandon as keeping the board's state — the SPEC's "open" degraded to what
    /// the data allows, never a silently different one.
    private func open() {
        if let url = presentation.item.url.flatMap(URL.init(string:)) {
            openURL(url)
        }
        onOpen()
    }

    private var applyButton: some View {
        Button(action: onApply) {
            Text(verbatim: applyLabel)
        }
        .buttonStyle(.borderedProminent)
        .focused($focusedControl, equals: .apply)
        .accessibilityHint(Text(verbatim:
            "Moves the item over its current state, which you have now seen. No keyboard shortcut applies this."))
    }

    private var sentence: String {
        "\(presentation.item.title) has changed on the board since Talos read it."
    }

    private var stateSentence: String {
        "Talos read it as \(Self.label(for: presentation.expected)); it is now \(Self.label(for: presentation.actual))."
    }

    private var provenanceSentence: String {
        guard let updatedBy = presentation.item.updatedBy else {
            return "Who changed it is unknown."
        }
        if let updatedAt = presentation.item.updatedAt {
            return "Changed by \(updatedBy) on \(updatedAt)."
        }
        return "Changed by \(updatedBy)."
    }

    private var applyLabel: String {
        "Move it to \u{201C}\(presentation.targetColumn)\u{201D} anyway"
    }

    /// The six internal states as a reader sees them — the dev-cycle names.
    static func label(for state: BoardState) -> String {
        switch state {
        case .backlog: "Backlog"
        case .ready: "Ready"
        case .inProgress: "In progress"
        case .inReview: "In review"
        case .done: "Done"
        case .blocked: "Blocked"
        }
    }
}

/// Presents a ``BoardConflictPromptCenter``'s current conflict as a sheet — the
/// system's own chrome, so Liquid Glass and its Reduce Transparency degradation
/// come for free.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Design-System#liquid-glass-is-inherited-never-applied
public extension View {
    /// Attaches the conflict-prompt sheet described above, bound to `center`.
    @MainActor
    func boardConflictPromptHost(_ center: BoardConflictPromptCenter) -> some View {
        sheet(item: Binding(
            get: { center.current },
            // A dismissal the controls did not drive — the window closing, the
            // app quitting — abandons the write fail-closed rather than
            // assuming a state.
            set: { newValue in
                if newValue == nil, let pending = center.current {
                    center.failClosed(pending.id)
                }
            }
        )) { pending in
            BoardConflictPromptView(
                presentation: pending.presentation,
                onKeep: { center.resolve(pending.id, with: .keepHumanState) },
                onApply: { center.resolve(pending.id, with: .applyMove) },
                onOpen: { center.resolve(pending.id, with: .openItem) }
            )
        }
    }
}
