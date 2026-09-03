import SwiftUI
import TalosAdapters

/// The streaming transcript: one virtualized row per ``SessionConsoleLine``,
/// dispatched through the ``OutputRendererRegistry`` a ``SessionConsoleViewModel``
/// carries — never a hardcoded Markdown path. `List` deallocates off-screen
/// rows, which is what keeps a long transcript inside the active-memory
/// budget and holds frame rate while scrolling.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable
@MainActor
public struct SessionConsoleView: View {
    private let viewModel: SessionConsoleViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollPhase: ScrollPhase = .idle

    /// How close to the bottom edge still counts as "at the bottom" — a
    /// small tolerance for layout rounding, not a debounce interval.
    private static let bottomProximityTolerance: CGFloat = 24

    public init(viewModel: SessionConsoleViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        switch viewModel.state {
        case .empty:
            emptyState
        case .loading:
            loadingState
        case .ready:
            transcript
        case let .failed(termination):
            VStack {
                if !viewModel.lines.isEmpty {
                    transcript
                }
                statusBanner(Self.failureCopy(for: termination), symbol: "exclamationmark.triangle")
            }
        case .denied:
            VStack {
                if !viewModel.lines.isEmpty {
                    transcript
                }
                statusBanner(Self.deniedCopy, symbol: "hand.raised")
            }
        }
    }

    private var emptyState: some View {
        Text(verbatim: "No output yet.")
            .foregroundStyle(.secondary)
            .padding()
            .accessibilityLabel(Text(verbatim: "No output yet"))
    }

    /// "Waiting for the first token" — the prompt is with the agent and it
    /// has not answered yet. The `ProgressView` is decorative: the text
    /// alone carries the state, so nothing here says anything by motion
    /// alone.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback
    private var loadingState: some View {
        HStack {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
            Text(verbatim: "Waiting for the agent to respond.")
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    /// Never colour alone: a text label and a distinct SF Symbol per kind,
    /// and the Failed and Denied symbols are visually distinct from each
    /// other so a denial never reads as an error. The symbol is
    /// accessibility-hidden and the text stands alone, the same split
    /// ``GatedDecisionLogRow``'s own outcome symbol uses.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#never-by-color-alone
    private func statusBanner(_ text: String, symbol: String) -> some View {
        HStack {
            Image(systemName: symbol)
                .accessibilityHidden(true)
            Text(verbatim: text)
        }
        .padding()
    }

    /// "What failed, where, and what state things are in now." No agent
    /// name: this view model is not told one, and inventing one would
    /// misattribute the words.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice
    private static func failureCopy(for termination: AgentTermination) -> String {
        switch termination.reason {
        case let .exited(code):
            "Exited with status \(code). Output above."
        case .failedToLaunch:
            "Failed to launch. No output was produced."
        case .denied, .stopped:
            // Unreachable: `SessionConsoleViewModel.state` only produces
            // `.failed(_:)` for `.exited` with a non-zero code or
            // `.failedToLaunch` — `.denied` and `.stopped` map to `.denied(_:)`
            // or `.ready` instead.
            "Exited with an unrecognized status. Output above."
        }
    }

    /// Neutral, never an error treatment — "Denied. Nothing was written." is
    /// the copy shape; this is the same shape for a run the gate ended
    /// rather than one gated write.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice
    private static let deniedCopy = "Denied. Session ended, nothing further ran."

    private var transcript: some View {
        ScrollViewReader { proxy in
            List(viewModel.lines) { line in
                row(for: line)
                    .id(line.id)
            }
            .onScrollPhaseChange { _, newPhase in
                scrollPhase = newPhase
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y
                    >= geometry.contentSize.height - geometry.containerSize.height - Self.bottomProximityTolerance
            } action: { _, isAtBottom in
                // `.idle` is a geometry read with no real scroll behind it,
                // and `.animating` is this view's own scroll-to-bottom call —
                // neither is the user scrolling.
                // https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#nothing-polls
                guard scrollPhase != .idle, scrollPhase != .animating else { return }
                if isAtBottom {
                    viewModel.resumeFollowingOutput()
                } else {
                    viewModel.pauseFollowingOutput()
                }
            }
            .onChange(of: viewModel.lines.last) { _, newValue in
                guard viewModel.isFollowingOutput, let lastID = newValue?.id else { return }
                scrollToBottom(lastID, proxy: proxy)
            }
            .onChange(of: pendingApprovalLineID) { _, newValue in
                // A pending approval "does not scroll out of reach", whether
                // or not it happens to be the last line and regardless of
                // the follow-output toggle — this is what puts the row where
                // the one sanctioned focus-move ("focus never moves on its
                // own", except when a new approval prompt appears) actually
                // lands on a control the user can see.
                // https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#focus
                guard let newValue else { return }
                scrollToBottom(newValue, proxy: proxy)
            }
        }
    }

    /// The id of the row currently pending an approval, if any — used only to
    /// keep that row in view when one appears; ``SessionConsoleViewModel``
    /// itself decides tier and outcome.
    private var pendingApprovalLineID: SessionConsoleLine.ID? {
        for line in viewModel.lines {
            guard case let .toolCall(call) = line.content, case .pending = call.approval else { continue }
            return line.id
        }
        return nil
    }

    /// Dispatches each row by content: agent output through the pluggable
    /// registry, unchanged; a tool call through its own row, which is where
    /// a pending approval renders — inline, in the row it belongs to, never
    /// a sheet.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
    @ViewBuilder
    private func row(for line: SessionConsoleLine) -> some View {
        switch line.content {
        case let .output(element):
            viewModel.renderers.view(for: element)
        case let .toolCall(call):
            SessionConsoleToolCallRow(call: call) { decision in
                viewModel.resolvePendingApproval(with: decision)
            }
        }
    }

    private func scrollToBottom(_ id: SessionConsoleLine.ID, proxy: ScrollViewProxy) {
        guard !reduceMotion else {
            proxy.scrollTo(id, anchor: .bottom)
            return
        }
        withAnimation {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }
}
