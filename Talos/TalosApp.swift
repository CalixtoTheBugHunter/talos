import AppKit
import SwiftUI
import TalosAdapters
import TalosCore
import TalosSafeguards
import TalosUI

/// Otherwise deliberately empty except for the approval-prompt and
/// denied-notice hosts — log export as a File-menu command rather than a
/// bespoke control means VoiceOver, keyboard reach, and contrast come from
/// `NSSavePanel`/`NSAlert` rather than from a Talos-authored surface there;
/// the approval prompt is the first Talos-authored one, so its menu commands
/// are wired here too.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#menus-carry-the-shortcuts
@main
struct TalosApp: App {
    @State private var approvalPromptCenter = ApprovalPromptCenter()
    @State private var deniedActionNoticeCenter = DeniedActionNoticeCenter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .approvalPromptHost(approvalPromptCenter)
                .deniedActionNoticeHost(deniedActionNoticeCenter)
                .task {
                    await seedApprovalPromptForUITestingIfRequested()
                    await seedDeniedActionNoticeForUITestingIfRequested()
                }
        }
        .commands {
            CommandGroup(after: .saveItem) {
                Button("Export Logs for Bug Report…") {
                    LogExportCommand.run()
                }
            }
            CommandGroup(after: .toolbar) {
                approveCommand
                denyCommand
            }
        }
    }

    /// Bound to the write-tier shortcut, and disabled — not just
    /// shortcut-less — while the pending request is irreversible: that tier
    /// is reachable "only by pointer, or by tabbing to the button [in the
    /// prompt itself] and activating it deliberately", so this menu command
    /// must not open a second path around that. See § Return never approves
    /// an irreversible action.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard
    private var approveCommand: some View {
        Button("Approve") {
            if let pending = approvalPromptCenter.current {
                approvalPromptCenter.resolve(pending.id, with: .allowed)
            }
        }
        .keyboardShortcut(KeyboardShortcut(.return, modifiers: .command))
        .disabled(approvalPromptCenter.current == nil || approvalPromptCenter.current?.tier == .irreversible)
    }

    private var denyCommand: some View {
        Button("Deny") {
            if let pending = approvalPromptCenter.current {
                approvalPromptCenter.resolve(pending.id, with: .denied)
            }
        }
        .keyboardShortcut(.cancelAction)
        .disabled(approvalPromptCenter.current == nil)
    }

    /// Exists only so `TalosUITests` can drive the real, mounted approval
    /// prompt before a Session Console or a live gate exists to raise one —
    /// the launch-environment key it reads is never set by a normal launch.
    @MainActor
    private func seedApprovalPromptForUITestingIfRequested() async {
        guard let tierName = ProcessInfo.processInfo.environment["TALOS_UI_TEST_PENDING_APPROVAL"] else { return }
        let tier: SafeguardsTier = tierName == "irreversible" ? .irreversible : .write
        let action: SafeguardsActionType = tier == .irreversible ? .fileDelete : .fileWrite
        let request = AgentPermissionRequest(
            id: "ui-test-\(tierName)",
            prompt: "The agent wants to delete build/ and 3 cache files in Sources/Talos/Legacy/."
        )
        _ = await approvalPromptCenter.present(request, action: action, tier: tier)
    }

    /// Exists for the same reason as the seed above, and for the same
    /// reason: `TalosUITests` needs to drive the real, mounted notice before
    /// a session ever runs one for real.
    @MainActor
    private func seedDeniedActionNoticeForUITestingIfRequested() async {
        guard let tierName = ProcessInfo.processInfo.environment["TALOS_UI_TEST_DENIED_NOTICE"] else { return }
        let action: SafeguardsActionType = tierName == "irreversible" ? .fileDelete : .fileWrite
        await deniedActionNoticeCenter.notify(
            action: action,
            requestPrompt: "The agent wants to delete build/ and 3 cache files in Sources/Talos/Legacy/."
        )
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
