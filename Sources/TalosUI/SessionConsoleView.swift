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
    private let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollPhase: ScrollPhase = .idle

    /// How close to the bottom edge still counts as "at the bottom" — a
    /// small tolerance for layout rounding, not a debounce interval.
    private static let bottomProximityTolerance: CGFloat = 24
    private static let tokenUsageBadgeTopPadding: CGFloat = 8

    /// The window minimum is `.contentMinSize`-derived: with no explicit floor
    /// the transcript's tall ideal becomes the window's minimum, which grows the
    /// window when a session opens the console. Declaring the same floor the
    /// start form (`ContentView`) does keeps the window minimum unchanged across
    /// form ↔ console, so the height is only ever the user's.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#what-is-restored-across-launch
    private static let minimumWidth: CGFloat = 420
    private static let minimumHeight: CGFloat = 260

    public init(
        viewModel: SessionConsoleViewModel,
        onClose: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !viewModel.isRunning {
                dismissControl
            }
            if let tokenUsage = viewModel.tokenUsage {
                tokenUsageBadge(tokenUsage, overheadRatio: viewModel.contextOverheadRatio)
            }
            if !viewModel.missingContextLabels.isEmpty {
                missingContextBadge(viewModel.missingContextLabels)
            }
            content
        }
        .frame(
            minWidth: Self.minimumWidth,
            maxWidth: .infinity,
            minHeight: Self.minimumHeight,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    /// A top-right ✕, shown once the session has ended, that closes the console
    /// so the user can start another — a single click, never behind a
    /// confirmation. Stop while running is the always-visible control the app
    /// hosts (`sessionStopHost`) plus `⌘.`, so this surface adds no second
    /// Stop of its own. See § The stop guarantee is an interaction rule
    /// (Foundations-Interaction-and-Keyboard).
    private var dismissControl: some View {
        HStack {
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "Close"))
            .accessibilityHint(Text(verbatim: "Closes this session so you can start another."))
        }
        .padding([.horizontal, .top])
    }

    @ViewBuilder
    private var content: some View {
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

    /// "Token usage for the running session" — the one line the console owes
    /// beside the transcript. Token counts "may be stated plainly", and an
    /// unmeasured report reads "Unavailable" rather than a zero; the overhead
    /// ratio, when known, is named so it reads as distinct from the agent's
    /// own count rather than folded into it.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice#cost-copy
    private func tokenUsageBadge(_ report: TokenReport, overheadRatio: Double?) -> some View {
        Text(verbatim: Self.tokenUsageCopy(report, overheadRatio: overheadRatio))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)
            .padding(.top, Self.tokenUsageBadgeTopPadding)
    }

    private static func tokenUsageCopy(_ report: TokenReport, overheadRatio: Double?) -> String {
        switch report {
        case let .measured(counts, model):
            let base = "\(counts.input) input · \(counts.output) output tokens (\(model))"
            guard let overheadRatio else { return base }
            let percent = Int((overheadRatio * 100).rounded())
            return "\(base) — about \(percent)% Talos-added token overhead"
        case let .unavailable(unavailable):
            return "Token usage unavailable — \(Self.unavailableReasonCopy(unavailable.reason))"
        }
    }

    private static func unavailableReasonCopy(_ reason: TokenUsageUnavailableReason) -> String {
        switch reason {
        case .notReported:
            "not yet reported"
        case .unrecognizedFormat:
            "session log format not recognized"
        }
    }

    /// Names the context parts an answer was produced without — a
    /// declared-absent Spec Drive is the case DoD criterion 4 turns on. On the output
    /// itself, not a banner the user leaves, and naming the part rather than
    /// calling the answer degraded. Carried by text, never colour or an error
    /// treatment: a missing input is not a failure.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback
    private func missingContextBadge(_ labels: [String]) -> some View {
        Text(verbatim: "Answered without \(labels.joined(separator: ", ")) context.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)
            .padding(.top, Self.tokenUsageBadgeTopPadding)
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
            // Start at the newest output. Only the initial offset — growth is
            // still the follow/pause logic below, so scrolling up to read stays
            // put. This also lands the transcript at the bottom when a session
            // ends: `.ready` renders the bare transcript but `.failed`/`.denied`
            // re-wrap it, so the `List` is rebuilt and would otherwise reset to
            // the top with no new line to trigger a follow scroll.
            // https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
            .defaultScrollAnchor(.bottom, for: .initialOffset)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
