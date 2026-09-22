import Foundation
import TalosAdapters
import TalosCore
import TalosOrchestration
import TalosPersistence
import TalosProjectLibrary
import TalosSafeguards
import TalosUI

/// Running one session through the shared pipeline, and continuing it with a
/// follow-up turn. Split out of `SessionComposer.swift` so that file's own
/// type- and file-length limits are not spent on the pipeline wiring, the same
/// reason `+BoardRefresh` and `+SpecDriveRefresh` are separate.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model
extension SessionComposer {
    /// Runs one session through the shared pipeline. Both a user's Assistant
    /// session and the Talos-authored refresh go through here, so the refresh
    /// gets the same gate, console, Stop, and record rather than its own path.
    /// A follow-up turn passes the prior run's `resumeToken`, which resumes the
    /// session and — by the same signal — assembles no fresh context.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions
    func runSession(
        root: URL,
        project: LoadedProject,
        intent: Intent,
        console: SessionConsoleViewModel,
        deniedNotices: DeniedActionNoticeCenter,
        resumeToken: String? = nil,
        sessionWillStart: (@MainActor () -> Void)? = nil
    ) async throws -> SessionRecord {
        let adapter = try AnyAgentAdapterBox(adapterRegistry.makeAdapter(named: project.declaration.adapter))
        let allowlist = try AllowlistStore(
            projectRoot: root,
            project: project.manifest.id,
            changeLog: NoOpAllowlistChangeLog()
        )
        let gate = TieredSafeguardsGate(allowlist: allowlist, approvalPrompt: console, connectors: project.connectors)
        let pipeline = await Self.makePipeline(
            adapter: adapter, gate: gate, database: database, project: project, root: root
        )
        let launch = SessionLaunch(
            agentName: project.declaration.name,
            configuration: AgentLaunchConfiguration(
                workingDirectory: root,
                environment: SpawnedAgentEnvironment.resolve(),
                resumeToken: resumeToken,
                model: project.declaration.model
            )
        )
        activeSession = ActiveSession(
            root: root,
            project: project,
            subFunction: intent.requestingSubFunction,
            resumeToken: resumeToken
        )
        presentConsole(console, intent: intent, resuming: resumeToken != nil, sessionWillStart: sessionWillStart)

        // A diverged board item stops an allowed move before it runs, per
        // decision 42. Only wired when the project declares a board; a read the
        // recognizer does not match never triggers it, so the board refresh's
        // own read carries it harmlessly.
        let boardConflict = project.board.map { makeBoardConflictResolver(root: root, board: $0) }
        // Run the pipeline in a task the Stop control cancels: a stop reaches
        // the pipeline as cancellation, which kills the agent at any suspension
        // the session can be sitting at. Tracking begins before the first await
        // and ends however the session does, so Stop is reachable throughout.
        // https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
        let sessionTask = Task {
            await pipeline.run(
                intent: intent,
                guideline: project.guideline,
                safeguards: project.safeguards,
                connectors: project.connectors,
                launch: launch,
                observer: { [console] event in await console.handle(event) },
                tokenObserver: { [console] update in await console.updateTokenUsage(update) },
                onDenial: { [deniedNotices] action, prompt in
                    await deniedNotices.notify(action: action, requestPrompt: prompt)
                },
                boardConflict: boardConflict
            )
        }
        stopCenter.beginTracking { sessionTask.cancel() }
        defer { stopCenter.sessionEnded() }
        let record = await sessionTask.value
        concludeSession(console, with: record)
        startNextQueuedFollowUp(console: console, deniedNotices: deniedNotices)
        return record
    }

    /// Sends `intentText` into the session the console shows — shown in the
    /// transcript at once, so the user sees their own turn immediately. If no
    /// turn is running it resumes right away; if one is, it is queued and sent
    /// when that turn ends, so the session is refined in sequence rather than
    /// run in parallel. The input is always enabled, which is why a mid-turn
    /// message is held rather than refused.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
    func submitFollowUp(
        intentText: String,
        console: SessionConsoleViewModel,
        deniedNotices: DeniedActionNoticeCenter
    ) async throws {
        console.appendUserMessage(intentText)
        guard !console.isRunning else {
            pendingFollowUps.append(intentText)
            return
        }
        try await resume(with: intentText, console: console, deniedNotices: deniedNotices)
    }

    /// Resumes the active session with `text` as the follow-up turn, using the
    /// prior run's own resume token. The resumed turn assembles no context — the
    /// agent already holds the prior conversation — so only the user's text
    /// reaches it, and every mutating tool call still hits the Safeguards gate.
    /// A no-op when there is nothing resumable, so a queued message never runs
    /// against a session that cannot continue.
    private func resume(
        with text: String,
        console: SessionConsoleViewModel,
        deniedNotices: DeniedActionNoticeCenter
    ) async throws {
        guard let active = activeSession, let resumeToken = active.resumeToken else { return }
        let intent = Intent(
            content: text,
            source: .userText,
            project: active.project.manifest.id,
            requestingSubFunction: active.subFunction
        )
        _ = try await runSession(
            root: active.root,
            project: active.project,
            intent: intent,
            console: console,
            deniedNotices: deniedNotices,
            resumeToken: resumeToken
        )
    }

    /// Drains one queued message as the just-ended turn's successor, on its own
    /// task so the completing run returns first. That successor drains the next
    /// on its own completion, so the queue empties one turn at a time in order.
    private func startNextQueuedFollowUp(console: SessionConsoleViewModel, deniedNotices: DeniedActionNoticeCenter) {
        guard !pendingFollowUps.isEmpty, activeSession?.resumeToken != nil else { return }
        let next = pendingFollowUps.removeFirst()
        Task { try? await resume(with: next, console: console, deniedNotices: deniedNotices) }
    }

    /// A fresh start resets the console before it is shown, so a new or failed
    /// start never reopens the previous session's transcript, and the user's
    /// own opening message is shown as the transcript's first line. A follow-up
    /// turn instead re-arms the running state while keeping the transcript, and
    /// its own message was already shown by ``submitFollowUp(intentText:console:deniedNotices:)``.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
    private func presentConsole(
        _ console: SessionConsoleViewModel,
        intent: Intent,
        resuming: Bool,
        sessionWillStart: (@MainActor () -> Void)?
    ) {
        if resuming {
            console.beginFollowUpTurn()
        } else {
            console.sessionStarted()
            if intent.source == .userText {
                console.appendUserMessage(intent.content)
            }
        }
        sessionWillStart?()
    }

    /// Tells the console how the run ended, labels any context that had nothing
    /// to assemble, and refreshes the token a follow-up turn resumes into. A
    /// clean turn carries the session's token forward; a stop or launch failure
    /// carries `nil`, which leaves nothing for a queued message to resume into.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback
    private func concludeSession(_ console: SessionConsoleViewModel, with record: SessionRecord) {
        console.noteUnavailableContext(record.unavailableContextParts)
        console.sessionConcluded(record.outcome)
        activeSession?.resumeToken = record.resumeToken
    }
}
