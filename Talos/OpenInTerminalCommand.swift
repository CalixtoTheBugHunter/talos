import AppKit
import Foundation
import TalosCore

/// The "Open Terminal Here…" menu command — "Talos opens your terminal
/// app... at the project path", one of the two hand-offs that make "Talos
/// is not just a terminal" a design choice rather than a missing feature.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-you-use-instead
@MainActor
enum OpenInTerminalCommand {
    static func run() {
        let panel = NSOpenPanel()
        panel.title = "Choose Project Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let projectPath = panel.url else { return }

        do {
            try ExternalAppHandoffCommands.handoff.openTerminal(atProjectPath: projectPath)
        } catch let error as MissingExternalAppError {
            ExternalAppHandoffCommands.presentMissingAppAlert(error)
        } catch {
            ExternalAppHandoffCommands.presentUnexpectedFailureAlert(role: .terminal)
        }
    }

    static func chooseApp() {
        ExternalAppHandoffCommands.chooseApp(for: .terminal)
    }
}
