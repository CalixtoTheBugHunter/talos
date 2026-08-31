import TalosOrchestration
import TalosProjectLibrary
import Testing

/// Drives a scheduler-sourced intent through every pipeline stage, which is the
/// claim that enabling a scheduled sub-function is a flag rather than a rewrite.
///
/// > Advisor and Self-improver will enter it from the **scheduler**. That is the
/// > only difference between them, and it is why the structure must be built
/// > once, now.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model
@Suite("A scheduler-sourced session")
struct SchedulerSourcedSessionTests {
    static func advisorSchedule(project: ProjectIdentifier = .generate()) -> SessionSchedule {
        SessionSchedule(
            id: "advisor-nightly",
            project: project,
            subFunction: .advisor,
            intentContent: "Review the project for missing edge cases.",
            interval: .seconds(3600)
        )
    }

    /// Every stage runs on the pipeline's existing entry point, called with the
    /// schedule's own intent and nothing else added for it.
    @Test("A schedule's intent runs the whole pipeline and is recorded")
    func aSchedulesIntentRunsTheWholePipeline() async {
        let project = ProjectIdentifier.generate()
        let schedule = Self.advisorSchedule(project: project)
        let adapter = ScriptedAgentAdapter(events: [terminated(.exited(code: 0))])
        let journal = SessionStageJournal()
        let writer = RecordingSessionRecordWriter(journal: journal)
        let memories = RecordingMemoriesUpdatePort(journal: journal)
        let pipeline = makeTestPipeline(adapter: adapter, recordWriter: writer, memories: memories)

        let record = await runTestSession(pipeline, intent: schedule.intent)

        #expect(record.outcome == .succeeded(TestDefaults.usage))
        #expect(record.project == project)
        #expect(record.subFunction == .advisor)
        #expect(await adapter.launchCount == 1)
        #expect(await writer.written == [record])
        #expect(await journal.stages == [.recordWritten, .memoriesUpdated])
        #expect(await memories.updated == [record])
    }

    /// Stage 3 is not skipped for a schedule: the prompt carries the assembled
    /// Project Library context, then the schedule's own text.
    @Test("A scheduled session is assembled from the Project Library like any other")
    func aScheduledSessionAssemblesContext() async {
        let schedule = Self.advisorSchedule()
        let adapter = ScriptedAgentAdapter(events: [terminated(.exited(code: 0))])
        let pipeline = makeTestPipeline(adapter: adapter)

        _ = await runTestSession(pipeline, intent: schedule.intent)

        let text = await adapter.sentPrompts.first?.text
        #expect(text?.contains("Never deploy on a Friday.") == true)
        #expect(text?.hasSuffix(schedule.intentContent) == true)
    }

    /// The regression this catches: any core stage branching on
    /// ``IntentSource`` would make these two runs diverge, and that branch is
    /// the refactor enabling Advisor is not allowed to need.
    ///
    /// > Enabling Advisor later must require **no refactor of Talos core**.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Sub-function-Advisor#what-the-mvp-must-deliver
    @Test("A scheduler-sourced run and a user-sourced run differ in nothing the pipeline produces")
    func theSourceChangesNothingThePipelineProduces() async {
        let project = ProjectIdentifier.generate()
        let schedule = Self.advisorSchedule(project: project)
        let typed = Intent(
            content: schedule.intentContent,
            source: .userText,
            project: project,
            requestingSubFunction: .advisor
        )

        let scheduledAdapter = ScriptedAgentAdapter(events: [terminated(.exited(code: 0))])
        let typedAdapter = ScriptedAgentAdapter(events: [terminated(.exited(code: 0))])

        let scheduled = await runTestSession(
            makeTestPipeline(adapter: scheduledAdapter),
            intent: schedule.intent
        )
        let fromUser = await runTestSession(
            makeTestPipeline(adapter: typedAdapter),
            intent: typed
        )

        #expect(scheduled == fromUser)
        #expect(await scheduledAdapter.sentPrompts == typedAdapter.sentPrompts)
    }
}
