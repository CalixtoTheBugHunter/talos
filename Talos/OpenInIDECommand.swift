import AppKit
import Foundation
import TalosCore

/// The "Open in IDE…" menu command — "Talos opens the affected files in
/// your preferred IDE", the hand-off that keeps "Talos never embeds a code
/// editor" a design choice rather than a missing feature.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#talos-is-not-a-vs-code-wrapper
@MainActor
enum OpenInIDECommand {
    static func run() {
        let panel = NSOpenPanel()
        panel.title = "Choose Files to Open"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        do {
            try ExternalAppHandoffCommands.handoff.openInIDE(files: panel.urls)
        } catch let error as MissingExternalAppError {
            ExternalAppHandoffCommands.presentMissingAppAlert(error)
        } catch {
            ExternalAppHandoffCommands.presentUnexpectedFailureAlert(role: .ide)
        }
    }

    static func chooseApp() {
        ExternalAppHandoffCommands.chooseApp(for: .ide)
    }
}
