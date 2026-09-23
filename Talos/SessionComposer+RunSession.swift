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
        startPendingSupersede(console: console, deniedNotices: deniedNotices)
        return record
    }

    /// Sends `intentText` into the session the console shows — shown in the
    /// transcript at once, so the user sees their own turn immediately. Per
    /// [decision 100] the message always reaches the agent: if a turn is
    /// running it *interrupts* that turn and supersedes it with a new one, and
    /// if none is running it is sent at once. The token to resume into is
    /// captured here, before the interrupt tears the running turn down and
    /// clears it. A fresh start is used when nothing is resumable.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
    func submitFollowUp(
        intentText: String,
        console: SessionConsoleViewModel,
        deniedNotices: DeniedActionNoticeCenter
    ) async throws {
        console.appendUserMessage(intentText)
        let resumeToken = activeSession?.resumeToken
        let decision = SessionFollowUpDecision.decide(
            isTurnRunning: console.isRunning, hasResumeToken: resumeToken != nil
        )
        let token = decision.resumesSameSession ? resumeToken : nil
        if decision.interruptsRunningTurn {
            // The running turn is stopped through the same path `⌘.` uses, which
            // fails the gate closed on any pending approval and kills the
            // process; the superseding turn starts once it has torn down, from
            // `startPendingSupersede`.
            pendingSupersede = PendingSupersede(text: intentText, resumeToken: token)
            stopCenter.requestStop()
        } else {
            try await resume(with: intentText, resumeToken: token, console: console, deniedNotices: deniedNotices)
        }
    }

    /// Sends `text` as the next turn of the session the console shows. With a
    /// `resumeToken` the same session resumes — assembling no context, since the
    /// agent already holds the prior conversation — so only the user's text
    /// reaches it; with `nil` a fresh session starts with `text` as its opening
    /// intent. Every mutating tool call still hits the Safeguards gate. A no-op
    /// when there is no session to reuse the project and root of.
    private func resume(
        with text: String,
        resumeToken: String?,
        console: SessionConsoleViewModel,
        deniedNotices: DeniedActionNoticeCenter
    ) async throws {
        guard let active = activeSession else { return }
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

    /// Starts the superseding turn a running turn was interrupted for, on its
    /// own task so the interrupted run returns first. It resumes the same
    /// session with the token captured at interrupt time, or — when none was
    /// captured, the interrupted turn having had no resumable session yet —
    /// starts fresh with the message as its opening intent. A no-op when no
    /// message is pending, which is the ordinary end of a turn nobody interrupted.
    private func startPendingSupersede(console: SessionConsoleViewModel, deniedNotices: DeniedActionNoticeCenter) {
        guard let pending = pendingSupersede else { return }
        pendingSupersede = nil
        Task {
            try? await resume(
                with: pending.text, resumeToken: pending.resumeToken, console: console, deniedNotices: deniedNotices
            )
        }
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
    /// to assemble, and refreshes the token a later follow-up resumes into. A
    /// clean turn carries the session's token forward; a stop or launch failure
    /// carries `nil`, so the next idle message starts fresh rather than resuming
    /// a session that cannot continue. A mid-turn supersede is unaffected: it
    /// captured its own token at interrupt time, before this cleared it.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback
    private func concludeSession(_ console: SessionConsoleViewModel, with record: SessionRecord) {
        console.noteUnavailableContext(record.unavailableContextParts)
        console.sessionConcluded(record.outcome)
        activeSession?.resumeToken = record.resumeToken
    }
}
