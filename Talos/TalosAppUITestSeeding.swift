import Foundation
import SwiftUI
import TalosAdapters
import TalosCore
import TalosOrchestration
import TalosProjectLibrary
import TalosSafeguards
import TalosUI

/// Every "seed real state for `TalosUITests`" helper `TalosApp` calls from
/// its own `.task` — a free-standing namespace, not an extension of
/// `TalosApp`, so its `@State` properties can stay `private` per
/// `private_swiftui_state` while still being seeded from here. Each function
/// takes exactly the collaborator or `Binding` it seeds, explicitly, rather
/// than reaching into `TalosApp` itself.
///
/// Split out of `TalosApp.swift` only because the real composition root
/// `AssistantSessionComposer.swift` adds pushed that file's own body past
/// this module's line-count limits, not because any of these helpers
/// changed. Each seeds a real, mounted control before a live session exists
/// to drive it for real, so `TalosUITests` can assert against it early.
@MainActor
enum TalosAppUITestSeeding {
    /// Exists only so `TalosUITests` can drive the real, mounted approval
    /// prompt before a Session Console or a live gate exists to raise one —
    /// the launch-environment key it reads is never set by a normal launch.
    static func seedApprovalPrompt(into center: ApprovalPromptCenter) async {
        guard let tierName = ProcessInfo.processInfo.environment["TALOS_UI_TEST_PENDING_APPROVAL"] else { return }
        let tier: SafeguardsTier = tierName == "irreversible" ? .irreversible : .write
        let action: SafeguardsActionType = tier == .irreversible ? .fileDelete : .fileWrite
        let request = AgentPermissionRequest(
            id: "ui-test-\(tierName)",
            prompt: "The agent wants to delete build/ and 3 cache files in Sources/Talos/Legacy/."
        )
        _ = await center.present(request, action: action, tier: tier)
    }

    /// Exists for the same reason as the seed above, and for the same
    /// reason: `TalosUITests` needs to drive the real, mounted notice before
    /// a session ever runs one for real.
    static func seedDeniedActionNotice(into center: DeniedActionNoticeCenter) async {
        guard let tierName = ProcessInfo.processInfo.environment["TALOS_UI_TEST_DENIED_NOTICE"] else { return }
        let action: SafeguardsActionType = tierName == "irreversible" ? .fileDelete : .fileWrite
        await center.notify(
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
    static func seedSessionStop(into center: SessionStopCenter) {
        guard ProcessInfo.processInfo.environment["TALOS_UI_TEST_SESSION_RUNNING"] != nil else { return }
        center.beginTracking(stopping: { await center.sessionEnded() })
    }

    /// Exists for the same reason as the two seeds above: `TalosUITests`
    /// needs to drive the real, mounted gated-decision-log view before any
    /// screen exists to host it — mounting behind real navigation is
    /// explicitly out of scope until one does.
    static func seedGatedDecisionLog(
        state: Binding<GatedDecisionLogViewModel.State>,
        isPresented: Binding<Bool>
    ) {
        guard let stateName = ProcessInfo.processInfo.environment["TALOS_UI_TEST_GATED_DECISION_LOG"] else { return }
        state.wrappedValue = seededGatedDecisionLogState(named: stateName)
        isPresented.wrappedValue = true
    }

    /// Exists for the same reason as the two seeds above: `TalosUITests`
    /// needs to drive the real, mounted session transcript before a real
    /// session ever streams output into one. The env var's value names which
    /// of ``SessionConsoleViewModel/State`` to seed, mirroring
    /// ``seedGatedDecisionLog(state:isPresented:)``'s `stateName` pattern —
    /// an unset var still means "don't seed", and an unrecognized value
    /// falls to the same full transcript this key always seeded before state
    /// names existed.
    static func seedSessionConsoleTranscript(
        viewModel: SessionConsoleViewModel,
        isPresented: Binding<Bool>
    ) {
        guard let stateName = ProcessInfo.processInfo.environment["TALOS_UI_TEST_SESSION_CONSOLE_TRANSCRIPT"] else {
            return
        }
        switch stateName {
        case "empty":
            break // `sessionStarted()` deliberately not called — nothing seeds `hasStarted`.
        case "loading":
            viewModel.sessionStarted()
        case "failed":
            seedTerminatedTranscript(viewModel: viewModel, reason: .exited(code: 1))
        case "denied":
            seedTerminatedTranscript(viewModel: viewModel, reason: .denied)
        case "tool-call-read":
            viewModel.sessionStarted()
            viewModel.handle(.toolCall(seededReadTierToolCall))
        case "tool-call-pending-write", "tool-call-pending-irreversible":
            viewModel.sessionStarted()
            let irreversible = stateName == "tool-call-pending-irreversible"
            seedPendingToolCallApproval(viewModel: viewModel, irreversible: irreversible)
        case "token-usage", "token-usage-unavailable":
            viewModel.sessionStarted()
            seedTokenUsage(viewModel: viewModel, unavailable: stateName == "token-usage-unavailable")
        default:
            viewModel.sessionStarted()
            for chunk in seededSessionConsoleTranscriptChunks {
                viewModel.appendOutput(chunk)
            }
        }
        isPresented.wrappedValue = true
    }

    /// The "failed" and "denied" seeds share everything but the termination
    /// reason.
    private static func seedTerminatedTranscript(viewModel: SessionConsoleViewModel, reason: AgentTerminationReason) {
        viewModel.sessionStarted()
        for chunk in seededSessionConsoleTerminationChunks {
            viewModel.appendOutput(chunk)
        }
        viewModel.handle(.terminated(AgentTermination(reason: reason)))
    }

    /// Exists only so `TalosUITests` can drive the real, mounted pending
    /// approval row before a live gate exists to raise one — the same reason
    /// `seedApprovalPrompt(into:)` exists, but for the inline row rather than
    /// the sheet. `present` is spawned on its own `Task` rather than awaited
    /// here, exactly as a real `TieredSafeguardsGate` would call it without
    /// blocking the caller that launched the session.
    private static func seedPendingToolCallApproval(viewModel: SessionConsoleViewModel, irreversible: Bool) {
        let tier: SafeguardsTier = irreversible ? .irreversible : .write
        let action: SafeguardsActionType = irreversible ? .fileDelete : .fileWrite
        let call = AgentToolCall(
            id: "ui-test-tool-call",
            name: irreversible ? "Delete" : "Write",
            targets: ["Sources/Talos/Legacy/Old.swift"]
        )
        viewModel.handle(.toolCall(call))
        let request = AgentPermissionRequest(
            id: call.id,
            prompt: irreversible
                ? "The agent wants to delete Sources/Talos/Legacy/Old.swift."
                : "The agent wants to modify Sources/Talos/Legacy/Old.swift."
        )
        Task { _ = await viewModel.present(request, action: action, tier: tier) }
    }

    /// Exists only so `TalosUITests` can drive the real, mounted token-usage
    /// badge before a live session ever reports usage — `unavailable` seeds
    /// the "Unavailable" state rather than a zero.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#when-the-log-format-changes
    private static func seedTokenUsage(viewModel: SessionConsoleViewModel, unavailable: Bool) {
        guard !unavailable else {
            viewModel.updateTokenUsage(SessionTokenUpdate(
                report: .unavailable(TokenUsageUnavailable(reason: .notReported)),
                contextOverheadRatio: 0
            ))
            return
        }
        let counts = TokenCounts(input: seededTokenInputCount, output: seededTokenOutputCount)
        viewModel.updateTokenUsage(SessionTokenUpdate(
            report: .measured(counts, model: "claude-opus-5"),
            contextOverheadRatio: seededTokenOverheadRatio
        ))
        for chunk in seededSessionConsoleTranscriptChunks {
            viewModel.appendOutput(chunk)
        }
    }

    private static let seededTokenInputCount = 1200
    private static let seededTokenOutputCount = 340
    private static let seededTokenOverheadRatio = 0.12

    /// A read-tier call never reaches the gate as a held request, so this
    /// row never moves past ``SessionConsoleToolCallApproval/notGated`` — the
    /// seed for "visible but visually de-emphasized, since they never
    /// prompt".
    private static let seededReadTierToolCall = AgentToolCall(
        id: "ui-test-read-call",
        name: "Read",
        targets: ["Sources/Talos/Legacy/Old.swift"]
    )

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

    /// The two lines a Failed or Denied seed shows above its status banner —
    /// short, since these seeds prove the banner renders over a real
    /// transcript rather than exercising scroll or memory budgets again.
    private static let seededSessionConsoleTerminationChunks: [AgentOutputChunk] = [
        AgentOutputChunk(channel: .standardOutput, text: "Reading the file tree.\n"),
        AgentOutputChunk(channel: .standardOutput, text: "Found 3 matches.\n")
    ]

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
