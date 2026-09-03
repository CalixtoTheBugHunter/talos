import AppKit
import Foundation
import SwiftUI
import TalosAdapters
import TalosCore
import TalosOrchestration
import TalosProjectLibrary
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
    @State private var sessionStopCenter = SessionStopCenter()
    @State private var isGatedDecisionLogPresented = false
    @State private var gatedDecisionLogState: GatedDecisionLogViewModel.State = .loading
    @State private var sessionConsoleViewModel = SessionConsoleViewModel()
    @State private var isSessionConsoleTranscriptPresented = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .approvalPromptHost(approvalPromptCenter)
                .deniedActionNoticeHost(deniedActionNoticeCenter)
                .sessionStopHost(sessionStopCenter)
                .sheet(isPresented: $isGatedDecisionLogPresented) {
                    GatedDecisionLogView(
                        state: gatedDecisionLogState,
                        onRetry: { seedGatedDecisionLogForUITestingIfRequested() }
                    )
                }
                .sheet(isPresented: $isSessionConsoleTranscriptPresented) {
                    SessionConsoleView(viewModel: sessionConsoleViewModel)
                }
                .task {
                    await seedApprovalPromptForUITestingIfRequested()
                    await seedDeniedActionNoticeForUITestingIfRequested()
                    seedGatedDecisionLogForUITestingIfRequested()
                    seedSessionStopForUITestingIfRequested()
                    seedSessionConsoleTranscriptForUITestingIfRequested()
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
                stopCommand
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

    /// The one app-scoped stop command, never a per-window copy: "`⌘.` is one
    /// app-scoped command, in the menu bar, with no per-window copy and no
    /// cross-window focus order to reason about" — bound here rather than on
    /// the visible control itself, so the guarantee does not depend on which
    /// view happens to be in the responder chain.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#stop-stays-reachable
    private var stopCommand: some View {
        Button("Stop session") {
            sessionStopCenter.requestStop()
        }
        .keyboardShortcut(".", modifiers: .command)
        .disabled(!sessionStopCenter.isSessionRunning)
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

    /// Exists for the same reason as the two seeds above: `TalosUITests`
    /// needs to drive the real, mounted Stop control before a real session
    /// ever starts one. The stop handler ends the tracked session rather than
    /// running a real process — proving the control is present, activates
    /// with no confirmation, is keyboard-reachable, and is VoiceOver-labeled
    /// does not require a process behind it, which the real adapter and
    /// process-tree tests own.
    @MainActor
    private func seedSessionStopForUITestingIfRequested() {
        guard ProcessInfo.processInfo.environment["TALOS_UI_TEST_SESSION_RUNNING"] != nil else { return }
        sessionStopCenter.beginTracking(stopping: { await sessionStopCenter.sessionEnded() })
    }

    /// Exists for the same reason as the two seeds above: `TalosUITests`
    /// needs to drive the real, mounted gated-decision-log view before any
    /// screen exists to host it — mounting behind real navigation is
    /// explicitly out of scope until one does.
    @MainActor
    private func seedGatedDecisionLogForUITestingIfRequested() {
        guard let stateName = ProcessInfo.processInfo.environment["TALOS_UI_TEST_GATED_DECISION_LOG"] else { return }
        gatedDecisionLogState = Self.seededGatedDecisionLogState(named: stateName)
        isGatedDecisionLogPresented = true
    }

    /// Exists for the same reason as the two seeds above: `TalosUITests`
    /// needs to drive the real, mounted session transcript before a real
    /// session ever streams output into one.
    @MainActor
    private func seedSessionConsoleTranscriptForUITestingIfRequested() {
        guard ProcessInfo.processInfo.environment["TALOS_UI_TEST_SESSION_CONSOLE_TRANSCRIPT"] != nil else { return }
        for chunk in Self.seededSessionConsoleTranscriptChunks {
            sessionConsoleViewModel.appendOutput(chunk)
        }
        isSessionConsoleTranscriptPresented = true
    }

    /// Three short lines plus one 100k+ character line with no newline, so a
    /// UI test and a manual scroll-performance pass both have a transcript
    /// long enough, and pathological enough, to exercise the active-memory
    /// and frame-rate budgets.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable
    private static let seededSessionConsoleTranscriptChunks: [AgentOutputChunk] = [
        AgentOutputChunk(channel: .standardOutput, text: "Reading the file tree.\n"),
        AgentOutputChunk(channel: .standardOutput, text: "Found 3 matches.\n"),
        AgentOutputChunk(
            channel: .standardOutput,
            text: String(repeating: "a", count: seededTranscriptLongLineLength)
        ),
        AgentOutputChunk(channel: .standardOutput, text: "\nDone.\n")
    ]
    private static let seededTranscriptLongLineLength = 120_000

    private static func seededGatedDecisionLogState(named name: String) -> GatedDecisionLogViewModel.State {
        switch name {
        case "loading":
            .loading
        case "empty":
            .empty
        case "failed":
            .failed("The decision log could not be read: the file is unreadable.")
        default:
            .ready(seededGatedDecisionLogEntries)
        }
    }

    /// A first and a second decision, spaced two minutes apart, so a UI test
    /// can see more than one row and both an irreversible denial and an
    /// allowlisted write-tier pass.
    private static let seededGatedDecisionLogEntries: [StoredGatedDecisionEntry] = {
        let project = ProjectIdentifier(rawValue: "ui-test-project")
        let firstTimestamp = Date(timeIntervalSince1970: seededGatedDecisionLogEpoch)
        let secondTimestamp = firstTimestamp.addingTimeInterval(seededGatedDecisionLogEntrySpacing)
        return [
            StoredGatedDecisionEntry(
                id: seededGatedDecisionLogFirstEntryID,
                project: project,
                sessionID: UUID(),
                timestamp: firstTimestamp,
                subFunction: .automator,
                requestID: "ui-test-1",
                requestPrompt: "The agent wants to delete build/ and 3 cache files in Sources/Talos/Legacy/.",
                action: .fileDelete,
                classification: .tier(.irreversible),
                actor: .user,
                outcome: .denied
            ),
            StoredGatedDecisionEntry(
                id: seededGatedDecisionLogSecondEntryID,
                project: project,
                sessionID: UUID(),
                timestamp: secondTimestamp,
                subFunction: .automator,
                requestID: "ui-test-2",
                requestPrompt: "The agent wants to commit Sources/App/Secrets.swift.",
                action: .gitCommit,
                classification: .tier(.write),
                actor: .allowlist,
                outcome: .allowed
            )
        ]
    }()

    /// An arbitrary but fixed instant, so a UI test sees a stable timestamp
    /// rather than the moment it happened to run.
    private static let seededGatedDecisionLogEpoch: TimeInterval = 1_700_000_000
    private static let seededGatedDecisionLogEntrySpacing: TimeInterval = 120
    private static let seededGatedDecisionLogFirstEntryID = 1
    private static let seededGatedDecisionLogSecondEntryID = 2
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
