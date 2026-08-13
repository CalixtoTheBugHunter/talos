import AppKit
import SwiftUI
import TalosCore

/// The Talos app shell.
///
/// Otherwise deliberately empty: this target exists so the project builds,
/// and the app shell is its own board item. Liquid Glass is inherited from
/// standard SwiftUI chrome and never applied by hand, per
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Design-System#liquid-glass-is-inherited-never-applied
///
/// The one real capability wired in here is log export — a File-menu
/// command rather than a bespoke control, so VoiceOver, keyboard reach, and
/// contrast come from `NSSavePanel`/`NSAlert` rather than from a Talos-authored
/// surface. It requires the explicit action of opening the menu and choosing
/// a destination, per https://github.com/CalixtoTheBugHunter/talos/issues/39.
@main
struct TalosApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .saveItem) {
                Button("Export Logs for Bug Report…") {
                    LogExportCommand.run()
                }
            }
        }
    }
}

/// The export flow behind the "Export Logs for Bug Report…" menu command.
/// A free-standing type, not a method on `TalosApp`, because `App` is a
/// value type recreated by SwiftUI and this flow owns no state across runs.
@MainActor
enum LogExportCommand {
    static func run() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "talos-logs.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task.detached {
            let succeeded: Bool
            do {
                try LogExporter.export(to: url)
                succeeded = true
            } catch {
                succeeded = false
            }
            await MainActor.run { presentResult(succeeded: succeeded) }
        }
    }

    private static func presentResult(succeeded: Bool) {
        let alert = NSAlert()
        alert.messageText = succeeded ? "Logs Exported" : "Export Failed"
        alert.informativeText = succeeded
            ? "Talos's local logs from this session were saved to the location you chose."
            : "Talos could not read or save the local logs."
        alert.alertStyle = succeeded ? .informational : .warning
        alert.runModal()
    }
}

/// Placeholder content. Carries no values of its own — no palette, type scale,
/// or spacing grid exists to pick from:
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Design-System#the-platform-is-the-design-system
struct ContentView: View {
    var body: some View {
        Text(verbatim: "Talos")
            .font(.largeTitle)
            .padding()
            .accessibilityLabel("Talos")
    }
}
