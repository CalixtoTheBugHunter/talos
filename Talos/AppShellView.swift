import SwiftUI
import TalosOrchestration
import TalosUI

/// Talos's one window: a sidebar and a content area, and nothing else. "Talos
/// is one window", so there is one view hierarchy regardless of how many
/// projects are open, and this is it.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#one-window
///
/// A two-column `NavigationSplitView` with **no third permanent column** and
/// **no fixed sidebar width** — the collapse at large text sizes is the
/// platform's, which is what lets "every surface holds its layout at 200%"
/// hold without Talos writing the layout math.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#checked-against-200-text-size
struct AppShellView: View {
    let composer: SessionComposer?
    let composerUnavailableReason: String?
    let consoleViewModel: SessionConsoleViewModel
    let deniedActionNoticeCenter: DeniedActionNoticeCenter
    @Bindable var navigation: ShellNavigationModel
    @Binding var isSessionConsolePresented: Bool

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
    }

    /// Single-selection `List` binds an optional; the shell always has a
    /// surface selected, so a deselect (nil) is ignored rather than clearing
    /// the content area.
    private var selectionBinding: Binding<ShellSurface?> {
        Binding(
            get: { navigation.selectedSurface },
            set: { newValue in
                if let newValue {
                    navigation.selectedSurface = newValue
                }
            }
        )
    }

    private var sidebar: some View {
        List(selection: selectionBinding) {
            // The sidebar's top level is Projects. The project store and the
            // add flow are their own work, so the section is present with an
            // empty state until then; selecting a project sets what the
            // surfaces below are about.
            // https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#every-surface-placed
            Section("Projects") {
                Text("No projects yet")
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(ShellSurface.allCases) { surface in
                    Label(surface.title, systemImage: surface.systemImage)
                        .tag(surface)
                }
            }
        }
        .navigationTitle("Talos")
    }

    /// Sends a follow-up turn into the session the console shows, through the
    /// same composer a start goes through. The console enables its input only
    /// once a resumable session is present, so the composer's own no-resumable-
    /// session guard is unreachable from here — swallowed rather than surfaced,
    /// since there is no path that reaches it.
    private func submitFollowUp(_ text: String) {
        guard let composer else { return }
        Task {
            try? await composer.submitFollowUp(
                intentText: text,
                console: consoleViewModel,
                deniedNotices: deniedActionNoticeCenter
            )
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.selectedSurface {
        case .sessions:
            // "The selected session opens in the content area as the Session
            // Console" — so the console is this surface's content once a
            // session is under way, and the start form is its pre-session
            // state, not a sheet layered over the window.
            // https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#every-surface-placed
            if isSessionConsolePresented {
                SessionConsoleView(
                    viewModel: consoleViewModel,
                    onClose: { isSessionConsolePresented = false },
                    onSubmitFollowUp: submitFollowUp
                )
            } else {
                ContentView(
                    composer: composer,
                    composerUnavailableReason: composerUnavailableReason,
                    consoleViewModel: consoleViewModel,
                    deniedActionNoticeCenter: deniedActionNoticeCenter,
                    isSessionConsolePresented: $isSessionConsolePresented
                )
            }
        default:
            PlaceholderSurfaceView(surface: navigation.selectedSurface)
        }
    }
}
