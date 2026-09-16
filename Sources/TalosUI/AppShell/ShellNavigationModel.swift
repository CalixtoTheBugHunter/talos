import Foundation
import Observation

/// The shell's navigation state: which top-level surface is shown, and which
/// project it is about. Cycling with `⌘⌥→` / `⌘⌥←` moves between surfaces and
/// "never changes the selected project" — the invariant this model enforces so
/// no surface has to remember it.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#moving-between-surfaces
///
/// The sidebar selection is restored across launch, so it is persisted on every
/// change — saved on change, never on a schedule.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#what-is-restored-across-launch
@MainActor
@Observable
public final class ShellNavigationModel {
    /// The top-level surface shown in the content area. Persisted on every
    /// change so it is restored on the next launch.
    public var selectedSurface: ShellSurface {
        didSet { defaults.set(selectedSurface.rawValue, forKey: Self.selectedSurfaceKey) }
    }

    /// The project every surface below the sidebar is about. Optional because
    /// the project store and add flow are their own work; cycling leaves this
    /// untouched whether or not one is selected.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library
    public var selectedProjectID: String?

    private let defaults: UserDefaults
    private static let selectedSurfaceKey = "talos.shell.selectedSurface"

    /// Restores the persisted sidebar selection, falling back to Sessions when
    /// none was saved or the saved value no longer names a surface.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.selectedSurfaceKey)
        selectedSurface = stored.flatMap(ShellSurface.init(rawValue:)) ?? .sessions
    }

    /// Moves to the next surface in sidebar order, wrapping — `⌘⌥→`.
    public func cycleForward() {
        selectedSurface = selectedSurface.next
    }

    /// Moves to the previous surface in sidebar order, wrapping — `⌘⌥←`.
    public func cycleBackward() {
        selectedSurface = selectedSurface.previous
    }
}
