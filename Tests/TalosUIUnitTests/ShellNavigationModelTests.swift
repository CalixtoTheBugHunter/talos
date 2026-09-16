import Foundation
import TalosUI
import Testing

/// Verifies ``ShellNavigationModel`` and ``ShellSurface`` against
/// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#moving-between-surfaces
/// — `⌘⌥→` / `⌘⌥←` "move to the next and previous top-level surface in the
/// sidebar, in sidebar order, wrapping at each end" and "never change the
/// selected project" — and against
/// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#what-is-restored-across-launch
/// — the sidebar selection is restored across launch.
@Suite("Shell navigation model")
struct ShellNavigationModelTests {
    /// An isolated store, so one test's persisted selection never leaks into
    /// another's restoration.
    private func freshDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "talos.shell.tests.\(UUID().uuidString)"))
    }

    @Test("Cycling forward moves through surfaces in sidebar order and wraps")
    @MainActor
    func cycleForwardWrapsInSidebarOrder() throws {
        let model = try ShellNavigationModel(defaults: freshDefaults())
        var seen: [ShellSurface] = [model.selectedSurface]

        for _ in ShellSurface.allCases {
            model.cycleForward()
            seen.append(model.selectedSurface)
        }

        // Starts at .sessions, visits every surface in order, and the last
        // step wraps back to the first.
        #expect(seen == [.sessions] + ShellSurface.allCases.dropFirst() + [.sessions])
        #expect(seen.last == .sessions)
    }

    @Test("Cycling backward wraps from the first surface to the last")
    @MainActor
    func cycleBackwardWrapsFromFirstToLast() throws {
        let model = try ShellNavigationModel(defaults: freshDefaults())
        #expect(model.selectedSurface == .sessions)

        model.cycleBackward()

        #expect(model.selectedSurface == ShellSurface.allCases.last)
    }

    @Test("Cycling never changes the selected project")
    @MainActor
    func cyclingNeverChangesTheSelectedProject() throws {
        let model = try ShellNavigationModel(defaults: freshDefaults())
        model.selectedProjectID = "project-42"

        model.cycleForward()
        model.cycleForward()
        model.cycleBackward()

        #expect(model.selectedProjectID == "project-42")
    }

    @Test("Selecting a surface is restored on the next launch")
    @MainActor
    func selectionIsRestoredOnNextLaunch() throws {
        let defaults = try freshDefaults()
        let first = ShellNavigationModel(defaults: defaults)

        first.selectedSurface = .monitor
        let relaunched = ShellNavigationModel(defaults: defaults)

        #expect(relaunched.selectedSurface == .monitor)
    }

    @Test("An absent stored selection falls back to Sessions")
    @MainActor
    func absentSelectionFallsBackToSessions() throws {
        let model = try ShellNavigationModel(defaults: freshDefaults())

        #expect(model.selectedSurface == .sessions)
    }
}
