import AppKit
import Foundation

/// The export flow behind the "Export Session Transcript…" menu command —
/// "Export produces a readable file (Markdown) including tool calls and
/// approvals." A free-standing type for the same reason ``LogExportCommand``
/// is: `App` is a value type SwiftUI recreates, and this flow owns no state
/// across runs.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
@MainActor
enum SessionTranscriptExportCommand {
    static func run(markdown: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "talos-session-transcript.md"
        panel.allowedContentTypes = [.text]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task.detached {
            let succeeded: Bool
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                succeeded = true
            } catch {
                succeeded = false
            }
            await MainActor.run { presentResult(succeeded: succeeded) }
        }
    }

    private static func presentResult(succeeded: Bool) {
        let alert = NSAlert()
        alert.messageText = succeeded ? "Transcript Exported" : "Export Failed"
        alert.informativeText = succeeded
            ? "The session transcript was saved to the location you chose."
            : "Talos could not save the transcript."
        alert.alertStyle = succeeded ? .informational : .warning
        alert.runModal()
    }
}
