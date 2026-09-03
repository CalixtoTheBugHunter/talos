import SwiftUI

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
        if viewModel.lines.isEmpty {
            emptyState
        } else {
            transcript
        }
    }

    private var emptyState: some View {
        Text(verbatim: "No output yet.")
            .foregroundStyle(.secondary)
            .padding()
            .accessibilityLabel(Text(verbatim: "No output yet"))
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            List(viewModel.lines) { line in
                viewModel.renderers.view(for: line.element)
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
