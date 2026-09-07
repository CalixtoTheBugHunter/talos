import AppKit
import Foundation
import TalosCore

/// Shared plumbing behind ``OpenInTerminalCommand`` and ``OpenInIDECommand``:
/// the real ``ExternalAppHandoff``, the "Choose…" override that makes both
/// roles configurable, and the failure alerts. A free-standing type for the
/// same reason ``LogExportCommand`` is one: `App` is a value type SwiftUI
/// recreates.
@MainActor
enum ExternalAppHandoffCommands {
    static let handoff = ExternalAppHandoff(
        resolver: ExternalAppResolver(isInstalled: NSWorkspaceExternalAppLauncher.isInstalled),
        preferences: preferences,
        launcher: NSWorkspaceExternalAppLauncher()
    )

    private static let preferences = UserDefaultsExternalAppPreferenceStore()

    /// Lets the user override auto-detection by picking any installed app —
    /// "Both are configurable". Uses `NSOpenPanel` rather than a bespoke
    /// picker for the same reason log/transcript export do: accessibility
    /// comes from the system panel.
    static func chooseApp(for role: ExternalAppRole) {
        let panel = NSOpenPanel()
        panel.title = role == .terminal ? "Choose Terminal App" : "Choose IDE"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK,
              let appURL = panel.url,
              let bundle = Bundle(url: appURL),
              let bundleIdentifier = bundle.bundleIdentifier
        else { return }

        let bundleName = bundle.infoDictionary?["CFBundleName"] as? String
        let name = bundleName ?? appURL.deletingPathExtension().lastPathComponent
        preferences.setConfiguredApp(ExternalAppCandidate(name: name, bundleIdentifier: bundleIdentifier), for: role)
    }

    /// "A missing configured app produces an actionable error" — `error.fix`
    /// is that actionable message, shown verbatim rather than paraphrased.
    static func presentMissingAppAlert(_ error: MissingExternalAppError) {
        let alert = NSAlert()
        alert.messageText = "Couldn't Open \(roleLabel(error.role))"
        alert.informativeText = error.fix
        alert.alertStyle = .warning
        alert.runModal()
    }

    static func presentUnexpectedFailureAlert(role: ExternalAppRole) {
        let alert = NSAlert()
        alert.messageText = "Couldn't Open \(roleLabel(role))"
        alert.informativeText = "Talos could not launch the app."
        alert.alertStyle = .warning
        alert.runModal()
    }

    private static func roleLabel(_ role: ExternalAppRole) -> String {
        role == .terminal ? "Terminal" : "IDE"
    }
}
