import TalosAdapters
import TalosOrchestration
import Testing

/// The response-liveness timeout, per decision 81: a session producing no
/// stream activity past the configured interval — while it is *not* waiting on
/// the Safeguards gate — ends as Failed, and the gate wait is never on that
/// clock, so a rank-4 guideline can never turn silence into a gate decision.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
@Suite("Session response liveness")
struct SessionResponseLivenessTests {
    @Test("A session silent past its response-liveness timeout ends failed, and the agent is killed")
    func silenceBeyondTheTimeoutFailsTheSession() async {
        let adapter = HangingAgentAdapter()
        let pipeline = SessionPipeline(
            assembler: makeTestAssembler(),
            preCheck: FixedSafeguardsPreCheck(),
            adapter: adapter,
            gate: RecordingSafeguardsGate(),
            decisionLog: RecordingGatedDecisionLog(),
            recordWriter: RecordingSessionRecordWriter(),
            memories: RecordingMemoriesUpdatePort()
        )

        let record = await pipeline.run(
            intent: makeTestIntent(),
            guideline: makeSessionGuideline(responseLivenessTimeout: .milliseconds(50)),
            safeguards: makeTestSafeguards(),
            connectors: makeTestConnectors(),
            launch: SessionLaunch(agentName: testAgentName, configuration: TestLaunch.configuration())
        )

        guard case let .failed(reason, _, _) = record.outcome else {
            Issue.record("Expected a silent session to end failed, got \(record.outcome)")
            return
        }
        #expect(reason.contains("no response"))
        // "A surviving child is a failed stop" — a timed-out session kills the
        // agent rather than leaving it running past the session that owns it.
        #expect(await adapter.stopCount == 1)
    }

    @Test("A session waiting on the Safeguards gate is never failed by the response-liveness timeout")
    func gateWaitIsNotTimed() async {
        let adapter = ScriptedAgentAdapter(events: [
            .permissionRequest(AgentPermissionRequest(id: "r1", prompt: "Delete 4 files", toolName: "Bash"))
        ])
        let gate = BlockingSafeguardsGate()
        let pipeline = SessionPipeline(
            assembler: makeTestAssembler(),
            preCheck: FixedSafeguardsPreCheck(),
            adapter: adapter,
            gate: gate,
            decisionLog: RecordingGatedDecisionLog(),
            recordWriter: RecordingSessionRecordWriter(),
            memories: RecordingMemoriesUpdatePort()
        )

        let session = Task {
            await pipeline.run(
                intent: makeTestIntent(),
                guideline: makeSessionGuideline(responseLivenessTimeout: .milliseconds(50)),
                safeguards: makeTestSafeguards(),
                connectors: makeTestConnectors(),
                launch: SessionLaunch(agentName: testAgentName, configuration: TestLaunch.configuration())
            )
        }
        for await _ in gate.reached {
            break
        }
        // Well past the 50 ms interval. Were the gate wait on the clock, the
        // session would already have failed on its own; only a stop can end it,
        // so a `.stopped` outcome is the proof the wait was never timed.
        try? await Task.sleep(for: .milliseconds(250))
        session.cancel()
        let record = await session.value

        #expect(record.outcome == .stopped(TestDefaults.usage))
    }
}
