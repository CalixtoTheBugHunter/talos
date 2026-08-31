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
        let journal = SessionStageJournal()
        let writer = RecordingSessionRecordWriter(journal: journal)
        let memories = RecordingMemoriesUpdatePort(journal: journal)
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
        // Stage 9 before stage 11, which the two counts above cannot tell from
        // the reverse: memories are updated for a session already recorded.
        #expect(await journal.stages == [.recordWritten, .memoriesUpdated])
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
            decisionLog: RecordingGatedDecisionLog(),
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

    /// An adapter that announces a call and then holds it produces both events
    /// for the one action. The gate answers the held request, once: gating the
    /// announcement as well would put two prompts and two log rows on a single
    /// action, and not gating the request at all would remove the gate.
    @Test("A call that is announced and then held is gated exactly once")
    func anAnnouncedThenHeldCallIsGatedOnce() async {
        let callID = "t1"
        let adapter = ScriptedAgentAdapter(events: [
            .toolCall(AgentToolCall(id: callID, name: "Write", targets: ["a.swift"])),
            .permissionRequest(AgentPermissionRequest(id: callID, prompt: "Write a.swift", toolName: "Write")),
            terminated(.exited(code: 0))
        ])
        let gate = RecordingSafeguardsGate(.allowed)
        let log = RecordingGatedDecisionLog()
        let pipeline = makeTestPipeline(adapter: adapter, gate: gate, decisionLog: log)

        _ = await runTestSession(pipeline)

        #expect(await gate.seenRequests.map(\.id) == [callID])
        #expect(await log.entries.count == 1)
        #expect(await adapter.carriedDecisions == [callID: .allowed])
    }

    /// "Every gated decision is **logged** with the actor, the action, the tier,
    /// and the outcome." Asserted on a denial, since that is the row a user most
    /// needs to find afterwards.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
    @Test("Every gated decision is logged with the actor, the action, the tier, and the outcome")
    func everyGatedDecisionIsLogged() async {
        let request = AgentPermissionRequest(id: "r1", prompt: "Delete 4 files in Sources/", toolName: "Bash")
        let adapter = ScriptedAgentAdapter(events: [.permissionRequest(request), terminated(.exited(code: 0))])
        let decision = SafeguardsDecision(
            outcome: .denied,
            action: SafeguardsActionType(rawValue: "file.delete"),
            tier: .irreversible,
            actor: .user
        )
        let log = RecordingGatedDecisionLog()
        let pipeline = makeTestPipeline(
            adapter: adapter,
            gate: RecordingSafeguardsGate(
                decision.outcome,
                action: decision.action,
                tier: decision.tier,
                decidedBy: decision.actor
            ),
            decisionLog: log
        )

        let project = ProjectIdentifier(rawValue: "p-7")
        _ = await runTestSession(pipeline, intent: makeTestIntent(project: project, requestingSubFunction: .automator))

        #expect(await log.entries == [GatedDecisionEntry(
            project: project,
            subFunction: .automator,
            request: request,
            decision: decision
        )])
    }

    /// "**A denial is a normal outcome.** The agent is told it was denied and
    /// continues" — so a session that carried a denial and then exited cleanly
    /// succeeded. The refusal is a row in the gated-decision log, not the
    /// outcome of the whole run.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
    @Test("A denied request is carried back and does not become the session's outcome")
    func aDenialDoesNotBecomeTheSessionsOutcome() async {
        let adapter = ScriptedAgentAdapter(events: [
            .permissionRequest(AgentPermissionRequest(id: "r1", prompt: "Delete the branch", toolName: "Bash")),
            terminated(.exited(code: 0))
        ])
        let log = RecordingGatedDecisionLog()
        let pipeline = makeTestPipeline(adapter: adapter, gate: RecordingSafeguardsGate(.denied), decisionLog: log)

        let record = await runTestSession(pipeline)

        #expect(record.outcome == .succeeded(TestDefaults.usage))
        #expect(await adapter.carriedDecisions == ["r1": .denied])
        #expect(await log.entries.map(\.outcome) == [.denied])
    }

    @Test("An agent that terminates for denial is recorded as denied")
    func agentReportedDenialIsRecordedAsDenied() async {
        let pipeline = makeTestPipeline(adapter: ScriptedAgentAdapter(events: [terminated(.denied)]))

        #expect(await runTestSession(pipeline).outcome == .denied(TestDefaults.usage))
    }

    // MARK: - What stage 3 could not fit

    /// "Context is dropped whole, in a declared order. Talos never truncates a
    /// context part, and **never drops one silently**" — and a dropped part is
    /// reported in the session, so the record names it.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#when-assembled-context-exceeds-the-ceiling
    @Test("A context part dropped for space is named on the session record")
    func droppedContextPartsReachTheRecord() async {
        let pipeline = makeTestPipeline(adapter: ScriptedAgentAdapter(events: [terminated(.exited(code: 0))]))
        // Room for the two pinned parts and nothing else, so memories drop.
        let ceiling = TokenEstimate.approximate("G") + TokenEstimate.approximate("S")

        let record = await pipeline.run(
            intent: makeTestIntent(),
            guideline: makeTestGuideline(context: ["memories"], tokenCeiling: ceiling, rawText: "G"),
            safeguards: makeTestSafeguards(rawText: "S"),
            connectors: makeTestConnectors(),
            launchConfiguration: TestLaunch.configuration()
        )

        #expect(record.outcome == .succeeded(TestDefaults.usage))
        #expect(record.droppedContextParts.map(\.kind) == [.memories])
    }

    // MARK: - Concurrent sessions on different projects

    /// "Concurrent sessions on different projects are isolated." Both sessions
    /// run the whole way through stages 5-8 at once, against one shared
    /// recorder: each gates its own request, carries its own decision back, and
    /// records its own outcome, so a session borrowing the other's shows up here
    /// as a wrong value rather than only as a wrong count.
    @Test("Two concurrent sessions each gate, answer, and record their own project's work")
    func concurrentSessionsAreIsolated() async {
        let writer = RecordingSessionRecordWriter()
        let projectA = ProjectIdentifier(rawValue: "project-a")
        let projectB = ProjectIdentifier(rawValue: "project-b")
        let adapterA = ScriptedAgentAdapter(events: [
            .permissionRequest(AgentPermissionRequest(id: "a1", prompt: "Write a.swift", toolName: "Write")),
            terminated(.exited(code: 0))
        ])
        let adapterB = ScriptedAgentAdapter(events: [
            .permissionRequest(AgentPermissionRequest(id: "b1", prompt: "Write b.swift", toolName: "Write")),
            terminated(.exited(code: 2), lastOutput: "error: refused")
        ])
        let logA = RecordingGatedDecisionLog()
        let logB = RecordingGatedDecisionLog()
        let first = makeTestPipeline(
            adapter: adapterA,
            gate: RecordingSafeguardsGate(.allowed),
            decisionLog: logA,
            recordWriter: writer
        )
        let second = makeTestPipeline(
            adapter: adapterB,
            gate: RecordingSafeguardsGate(.denied),
            decisionLog: logB,
            recordWriter: writer
        )

        async let recordA = runTestSession(first, intent: makeTestIntent(project: projectA))
        async let recordB = runTestSession(second, intent: makeTestIntent(project: projectB))
        let (resultA, resultB) = await (recordA, recordB)

        #expect(resultA.project == projectA)
        #expect(resultA.outcome == .succeeded(TestDefaults.usage))
        #expect(resultB.project == projectB)
        #expect(resultB.outcome == .failed(
            reason: "The agent exited with code 2.",
            lastOutput: "error: refused",
            tokenReport: TestDefaults.usage
        ))
        #expect(await adapterA.carriedDecisions == ["a1": .allowed])
        #expect(await adapterB.carriedDecisions == ["b1": .denied])
        #expect(await logA.entries.map(\.project) == [projectA])
        #expect(await logB.entries.map(\.project) == [projectB])
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
