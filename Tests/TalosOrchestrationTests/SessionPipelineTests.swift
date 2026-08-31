import TalosAdapters
import TalosOrchestration
import TalosProjectLibrary
import TalosSafeguards
import Testing

/// Verifies the shared session model's ordering, which is the safety property:
/// "pre-check before run, gate before every mutation, record after."
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model
@Suite("Session pipeline")
struct SessionPipelineTests {
    // MARK: - Every stage, in order

    /// "States model every SPEC stage in order, from intent through
    /// memories-updated."
    @Test("A happy path runs every stage in order and ends with memories updated")
    func happyPathRunsEveryStageInOrder() async {
        let preCheck = FixedSafeguardsPreCheck(.approved)
        let adapter = ScriptedAgentAdapter(events: [
            .output(AgentOutputChunk(channel: .standardOutput, text: "Working.")),
            .toolCall(AgentToolCall(id: "t1", name: "Read", targets: ["README.md"])),
            terminated(.exited(code: 0))
        ])
        let writer = RecordingSessionRecordWriter()
        let memories = RecordingMemoriesUpdatePort()
        let pipeline = makeTestPipeline(
            preCheck: preCheck,
            adapter: adapter,
            recordWriter: writer,
            memories: memories
        )

        let record = await runTestSession(pipeline)

        #expect(record.outcome == .succeeded(TestDefaults.usage))
        #expect(preCheck.evaluatedInputs.count == 1)
        #expect(await adapter.launchCount == 1)
        #expect(await adapter.sentPrompts.count == 1)
        #expect(await writer.written == [record])
        #expect(await memories.updated == [record])
        // An agent that terminated on its own is never stopped on top of that.
        #expect(await adapter.stopCount == 0)
    }

    /// Stage 3's output is what reaches the agent — the assembled parts, then
    /// the intent's own text.
    @Test("The prompt sent to the agent carries the assembled context and the intent")
    func promptCarriesAssembledContext() async {
        let adapter = ScriptedAgentAdapter(events: [terminated(.exited(code: 0))])
        let pipeline = makeTestPipeline(adapter: adapter)

        let intent = makeTestIntent(content: "Add a dark mode toggle.")
        _ = await runTestSession(pipeline, intent: intent)

        let text = await adapter.sentPrompts.first?.text
        #expect(text?.contains("Never deploy on a Friday.") == true)
        #expect(text?.hasSuffix("Add a dark mode toggle.") == true)
    }

    /// A `.toolCall` is forwarded and never gated; a `.permissionRequest` is
    /// always gated. "A tool call and a permission request are two distinct
    /// event types" — collapsing them removes the gate.
    @Test("Streamed events reach the console observer in the order the agent produced them")
    func streamedEventsReachTheObserverInOrder() async {
        let events: [AgentEvent] = [
            .output(AgentOutputChunk(channel: .standardOutput, text: "one")),
            .toolCall(AgentToolCall(id: "t1", name: "Write", targets: ["a.swift"])),
            terminated(.exited(code: 0))
        ]
        let pipeline = makeTestPipeline(adapter: ScriptedAgentAdapter(events: events))

        let seen = RecordingObserver()
        _ = await runTestSession(pipeline, observer: { await seen.record($0) })

        #expect(await seen.events == events)
    }

    // MARK: - The pre-check cannot be bypassed

    /// "The Safeguards pre-check cannot be bypassed to reach the running
    /// state." Skipping stage 4 is a *compile* error — `SafeguardsApproved` has
    /// no public initializer and `runSafeguardsPreCheck(using:)` is the only
    /// thing that returns one — so what remains to assert at runtime is that a
    /// denial never reaches the adapter.
    @Test("A pre-check denial never launches the agent")
    func preCheckDenialNeverLaunchesTheAgent() async {
        let adapter = ScriptedAgentAdapter(events: [terminated(.exited(code: 0))])
        let gate = RecordingSafeguardsGate()
        let pipeline = makeTestPipeline(
            preCheck: FixedSafeguardsPreCheck(.denied(reason: "Production deploys need a human.")),
            adapter: adapter,
            gate: gate
        )

        let record = await runTestSession(pipeline)

        #expect(record.outcome == .safeguardsPreCheckDenied(reason: "Production deploys need a human."))
        #expect(await adapter.launchCount == 0)
        #expect(await adapter.sentPrompts.isEmpty)
        #expect(await gate.seenRequests.isEmpty)
    }

    /// The pre-check judges the session it was handed, not a default.
    @Test("The pre-check sees the requesting project and sub-function")
    func preCheckSeesTheRequestingSession() async {
        let preCheck = FixedSafeguardsPreCheck(.approved)
        let pipeline = makeTestPipeline(
            preCheck: preCheck,
            adapter: ScriptedAgentAdapter(events: [terminated(.exited(code: 0))])
        )

        let intent = makeTestIntent(project: ProjectIdentifier(rawValue: "p-1"), requestingSubFunction: .automator)
        _ = await runTestSession(pipeline, intent: intent)

        #expect(preCheck.evaluatedInputs.first?.project == ProjectIdentifier(rawValue: "p-1"))
        #expect(preCheck.evaluatedInputs.first?.subFunction == .automator)
    }

    /// Stage 3 failing is **Failed, not Denied** — "nothing was gated and the
    /// user refused nothing" — and it still never reaches the agent.
    @Test("A context-assembly overflow is recorded as failed assembly, not as a denial")
    func assemblyOverflowNeverLaunchesTheAgent() async {
        let adapter = ScriptedAgentAdapter(events: [terminated(.exited(code: 0))])
        let preCheck = FixedSafeguardsPreCheck(.approved)
        let writer = RecordingSessionRecordWriter()
        let pipeline = SessionPipeline(
            assembler: makeTestAssembler(),
            preCheck: preCheck,
            adapter: adapter,
            gate: RecordingSafeguardsGate(),
            recordWriter: writer,
            memories: RecordingMemoriesUpdatePort()
        )

        let record = await pipeline.run(
            intent: makeTestIntent(),
            // A ceiling the two pinned parts alone cannot fit.
            guideline: makeTestGuideline(context: ["memories"], tokenCeiling: 1),
            safeguards: makeTestSafeguards(),
            connectors: makeTestConnectors(),
            launchConfiguration: TestLaunch.configuration()
        )

        guard case .contextAssemblyFailed = record.outcome else {
            Issue.record("Expected a pinned-overflow assembly failure, got \(record.outcome)")
            return
        }
        #expect(preCheck.evaluatedInputs.isEmpty)
        #expect(await adapter.launchCount == 0)
        #expect(await writer.written.count == 1)
    }

    // MARK: - Every mutating call hits the gate

    @Test("Every permission request is routed through the gate and the decision carried back")
    func everyPermissionRequestIsGated() async {
        let requests = [
            AgentPermissionRequest(id: "r1", prompt: "Write a.swift", toolName: "Write"),
            AgentPermissionRequest(id: "r2", prompt: "Write b.swift", toolName: "Write")
        ]
        let adapter = ScriptedAgentAdapter(events:
            requests.map { .permissionRequest($0) } + [terminated(.exited(code: 0))])
        let gate = RecordingSafeguardsGate(.allowed)
        let pipeline = makeTestPipeline(adapter: adapter, gate: gate)

        let intent = makeTestIntent(project: ProjectIdentifier(rawValue: "p-9"))
        _ = await runTestSession(pipeline, intent: intent)

        #expect(await gate.seenRequests == requests)
        #expect(await gate.seenProjects.allSatisfy { $0 == ProjectIdentifier(rawValue: "p-9") })
        #expect(await adapter.carriedDecisions == ["r1": .allowed, "r2": .allowed])
    }

    /// "Denial is not failure" — a session the user refused is recorded and
    /// rendered as denied, never as an error.
    @Test("A denied request makes the session denied, not failed")
    func denialIsNotFailure() async {
        let adapter = ScriptedAgentAdapter(events: [
            .permissionRequest(AgentPermissionRequest(id: "r1", prompt: "Delete the branch", toolName: "Bash")),
            terminated(.exited(code: 0))
        ])
        let pipeline = makeTestPipeline(adapter: adapter, gate: RecordingSafeguardsGate(.denied))

        let record = await runTestSession(pipeline)

        #expect(record.outcome == .denied(TestDefaults.usage))
        #expect(await adapter.carriedDecisions == ["r1": .denied])
    }

    @Test("An agent that terminates for denial is recorded as denied")
    func agentReportedDenialIsRecordedAsDenied() async {
        let pipeline = makeTestPipeline(adapter: ScriptedAgentAdapter(events: [terminated(.denied)]))

        #expect(await runTestSession(pipeline).outcome == .denied(TestDefaults.usage))
    }

    // MARK: - Concurrent sessions on different projects

    /// "Concurrent sessions on different projects are isolated." Two sessions
    /// run at once against one shared recorder: each record carries its own
    /// project and outcome, and neither borrows the other's.
    @Test("Two concurrent sessions on different projects keep their own outcomes")
    func concurrentSessionsAreIsolated() async {
        let writer = RecordingSessionRecordWriter()
        let first = makeTestPipeline(
            preCheck: FixedSafeguardsPreCheck(.approved),
            adapter: ScriptedAgentAdapter(events: [terminated(.exited(code: 0))]),
            recordWriter: writer
        )
        let second = makeTestPipeline(
            preCheck: FixedSafeguardsPreCheck(.denied(reason: "Not for this project.")),
            adapter: ScriptedAgentAdapter(events: [terminated(.exited(code: 0))]),
            recordWriter: writer
        )
        let projectA = ProjectIdentifier(rawValue: "project-a")
        let projectB = ProjectIdentifier(rawValue: "project-b")

        async let recordA = runTestSession(first, intent: makeTestIntent(project: projectA))
        async let recordB = runTestSession(second, intent: makeTestIntent(project: projectB))
        let (resultA, resultB) = await (recordA, recordB)

        #expect(resultA.project == projectA)
        #expect(resultA.outcome == .succeeded(TestDefaults.usage))
        #expect(resultB.project == projectB)
        #expect(resultB.outcome == .safeguardsPreCheckDenied(reason: "Not for this project."))
        #expect(await writer.written.count == 2)
    }
}

/// Collects what the pipeline streamed to the console, in order.
private actor RecordingObserver {
    private(set) var events: [AgentEvent] = []

    func record(_ event: AgentEvent) {
        events.append(event)
    }
}
