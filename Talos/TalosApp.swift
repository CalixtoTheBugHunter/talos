import AppKit
import Foundation
import SwiftUI
import TalosAdapters
import TalosCore
import TalosOrchestration
import TalosPersistence
import TalosProjectLibrary
import TalosSafeguards
import TalosUI

/// Otherwise deliberately empty except for the approval-prompt and denied-notice hosts — log and transcript
/// export, and the terminal/IDE hand-off, are File-menu commands rather than bespoke controls, so VoiceOver,
/// keyboard reach, and contrast come from `NSSavePanel`/`NSAlert`/`NSOpenPanel`; the approval prompt is the
/// first Talos-authored surface, so its menu commands are wired here too.
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
    /// `nil` until the local database has opened — the one real entry point
    /// Assistant's composition root needs. Absent rather than defaulted on
    /// failure, so `ContentView` can disable starting a session instead of
    /// starting one against a database that never opened.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Sub-function-Assistant#pipeline
    @State private var assistantSessionComposer: AssistantSessionComposer?
    @State private var databaseOpenErrorMessage: String?

    var body: some Scene {
        WindowGroup {
            ContentView(
                composer: assistantSessionComposer,
                composerUnavailableReason: databaseOpenErrorMessage,
                consoleViewModel: sessionConsoleViewModel,
                deniedActionNoticeCenter: deniedActionNoticeCenter,
                isSessionConsolePresented: $isSessionConsoleTranscriptPresented
            )
            .approvalPromptHost(approvalPromptCenter)
            .deniedActionNoticeHost(deniedActionNoticeCenter)
            .sessionStopHost(sessionStopCenter)
            .sheet(isPresented: $isGatedDecisionLogPresented) {
                GatedDecisionLogView(
                    state: gatedDecisionLogState,
                    onRetry: {
                        TalosAppUITestSeeding.seedGatedDecisionLog(
                            state: $gatedDecisionLogState,
                            isPresented: $isGatedDecisionLogPresented
                        )
                    }
                )
            }
            .sheet(isPresented: $isSessionConsoleTranscriptPresented) {
                SessionConsoleView(viewModel: sessionConsoleViewModel)
            }
            .task {
                // Opened on its own, unawaited task: this does real disk I/O
                // (directory creation, `sqlite3_open_v2`, migrations) that
                // has nothing to do with the seeds below, and awaiting it
                // first measurably delayed every one of them past the fixed
                // waits `TalosUITests` seeds against.
                Task { await openLocalDatabase() }
                await TalosAppUITestSeeding.seedApprovalPrompt(into: approvalPromptCenter)
                await TalosAppUITestSeeding.seedDeniedActionNotice(into: deniedActionNoticeCenter)
                TalosAppUITestSeeding.seedGatedDecisionLog(
                    state: $gatedDecisionLogState,
                    isPresented: $isGatedDecisionLogPresented
                )
                TalosAppUITestSeeding.seedSessionStop(into: sessionStopCenter)
                TalosAppUITestSeeding.seedSessionConsoleTranscript(
                    viewModel: sessionConsoleViewModel,
                    isPresented: $isSessionConsoleTranscriptPresented
                )
            }
        }
        .commands {
            CommandGroup(after: .saveItem) {
                Button("Export Logs for Bug Report…") {
                    LogExportCommand.run()
                }
                Button("Export Session Transcript…") {
                    SessionTranscriptExportCommand.run(markdown: sessionConsoleViewModel.exportMarkdown())
                }.disabled(sessionConsoleViewModel.lines.isEmpty)
            }
            CommandGroup(after: .toolbar) {
                approveCommand
                denyCommand
                stopCommand
            }
            HandOffCommands()
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

    /// Opens the one local SQLite database every session record and gated
    /// decision is written to, applying every migration in the order each
    /// schema's own comment declares, then hands it to a fresh
    /// ``AssistantSessionComposer``. A failure here disables starting a
    /// session rather than starting one with nowhere to record it.
    @MainActor
    private func openLocalDatabase() async {
        do {
            let database = try await Database(
                url: DatabaseLocation.defaultDatabaseURL(),
                migrations: [
                    SessionRecordsSchema.migration,
                    GatedDecisionLogSchema.migration,
                    SessionTranscriptSchema.migration
                ]
            )
            assistantSessionComposer = AssistantSessionComposer(database: database, stopCenter: sessionStopCenter)
        } catch {
            databaseOpenErrorMessage = "Talos could not open its local database: \(error)"
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
