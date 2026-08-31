import TalosAdapters
import TalosOrchestration
import TalosProjectLibrary
import TalosSafeguards
import Testing

/// Verifies that a session survives every abnormal ending — agent crash, user
/// stop, a denial, and a stream that ends without terminating — leaving a
/// record written exactly once and nothing still running. Ordering and the
/// gate route live in `SessionPipelineTests`.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree
@Suite("Session pipeline termination")
struct SessionPipelineTerminationTests {
    // MARK: - Stop, denial, and crash leave no corrupt state

    /// "A session survives agent crash, user stop, and denial without corrupt
    /// state" — each lands on its own outcome, and each still writes a record.
    @Test("An agent that reports it was stopped is recorded as stopped, exactly once")
    func reportedStopIsRecordedOnce() async {
        let writer = RecordingSessionRecordWriter()
        let memories = RecordingMemoriesUpdatePort()
        let pipeline = makeTestPipeline(
            adapter: ScriptedAgentAdapter(events: [terminated(.stopped)]),
            recordWriter: writer,
            memories: memories
        )

        let record = await runTestSession(pipeline)

        #expect(record.outcome == .stopped(TestDefaults.usage))
        #expect(await writer.written.count == 1)
        #expect(await memories.updated.count == 1)
    }

    /// "The user can **stop any running session immediately**, and stop means the
    /// process is killed." The stop arrives as cancellation while a prompt is
    /// pending — the state a session sits in longest, and the one where a gate
    /// with no deadline would otherwise hold the session open forever.
    ///
    /// The gate's own answer is a denial attributed to Talos, since the user
    /// never decided, and it is logged as one. It is not carried back: the agent
    /// it would have told is dead.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
    @Test("A stop while a prompt is pending kills the agent and records the session as stopped")
    func aStopWhileAPromptIsPendingKillsTheAgent() async {
        let adapter = ScriptedAgentAdapter(events: [
            .permissionRequest(AgentPermissionRequest(id: "r1", prompt: "Delete 4 files", toolName: "Bash")),
            terminated(.exited(code: 0))
        ])
        let gate = BlockingSafeguardsGate()
        let log = RecordingGatedDecisionLog()
        let writer = RecordingSessionRecordWriter()
        let pipeline = makeTestPipeline(adapter: adapter, gate: gate, decisionLog: log, recordWriter: writer)

        let session = Task { await runTestSession(pipeline) }
        for await _ in gate.reached {
            break
        }
        session.cancel()
        let record = await session.value

        #expect(record.outcome == .stopped(TestDefaults.usage))
        #expect(await adapter.stopCount == 1)
        #expect(await adapter.carriedDecisions.isEmpty)
        #expect(await log.entries.map(\.actor) == [.talos])
        #expect(await log.entries.map(\.outcome) == [.denied])
        #expect(await writer.written.count == 1)
    }

    /// The stream ends in an error rather than a `.terminated` event.
    @Test("An agent crash mid-stream is recorded as failed, exactly once")
    func agentCrashIsRecordedOnce() async {
        let writer = RecordingSessionRecordWriter()
        let adapter = ScriptedAgentAdapter(
            events: [.output(AgentOutputChunk(channel: .standardOutput, text: "Working."))],
            crash: AgentNotRunningError(fix: "The agent process exited unexpectedly. Start the session again.")
        )
        let pipeline = makeTestPipeline(adapter: adapter, recordWriter: writer)

        let record = await runTestSession(pipeline)

        guard case let .failed(reason, lastOutput, tokenReport) = record.outcome else {
            Issue.record("Expected a crash to be recorded as failed, got \(record.outcome)")
            return
        }
        #expect(reason == "The agent process exited unexpectedly. Start the session again.")
        // The agent's own last words, which a crash has no termination event to
        // carry: without them the failure names no state the user can act on.
        #expect(lastOutput == "Working.")
        #expect(tokenReport == TestDefaults.usage)
        #expect(await writer.written.count == 1)
        #expect(await adapter.stopCount == 1)
    }

    /// "A surviving child is a failed stop, not a partial one." An agent left
    /// running past the session that owns it acts outside the gate, so every
    /// exit without a `.terminated` event kills it first.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree
    @Test("A stream that ends without terminating still kills the agent")
    func silentStreamEndStillKillsTheAgent() async {
        let adapter = ScriptedAgentAdapter(events: [])
        let pipeline = makeTestPipeline(adapter: adapter)

        _ = await runTestSession(pipeline)

        #expect(await adapter.stopCount == 1)
    }

    /// The adapter broke between the gate deciding and the agent being told, so
    /// the agent is running with an unanswered request. Killing it is the only
    /// outcome that leaves nothing acting ungated.
    @Test("An adapter that cannot carry a decision back kills the agent and records a failure")
    func undeliverableDecisionKillsTheAgent() async {
        let adapter = ScriptedAgentAdapter(
            events: [
                .permissionRequest(AgentPermissionRequest(id: "r1", prompt: "Write a.swift", toolName: "Write")),
                terminated(.exited(code: 0))
            ],
            resolveFailure: AgentNotRunningError(fix: "The agent stopped accepting decisions.")
        )
        let writer = RecordingSessionRecordWriter()
        let pipeline = makeTestPipeline(adapter: adapter, recordWriter: writer)

        let record = await runTestSession(pipeline)

        #expect(record.outcome == .failed(
            reason: "The agent stopped accepting decisions.",
            tokenReport: TestDefaults.usage
        ))
        #expect(await adapter.stopCount == 1)
        #expect(await writer.written.count == 1)
    }

    /// A stream that ends with no `.terminated` event at all — the adapter
    /// contract says one is always last, so its absence is a crash too.
    @Test("A stream that ends without terminating is recorded as failed")
    func silentStreamEndIsRecordedAsFailed() async {
        let pipeline = makeTestPipeline(adapter: ScriptedAgentAdapter(events: []))

        guard case .failed = await runTestSession(pipeline).outcome else {
            Issue.record("Expected a stream with no termination event to be recorded as failed")
            return
        }
    }

    /// Failure copy names "**what failed, where, and what state things are
    /// in**", so the agent's own final output is carried rather than dropped or
    /// paraphrased — a message that drops the state clause sends the user to a
    /// terminal to learn what Talos already knew.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice
    @Test("A non-zero exit is recorded as failed with the code named and the agent's last output kept")
    func nonZeroExitNamesTheCode() async {
        let adapter = ScriptedAgentAdapter(events: [
            terminated(.exited(code: 2), lastOutput: "fatal: could not read config")
        ])
        let pipeline = makeTestPipeline(adapter: adapter)

        #expect(await runTestSession(pipeline).outcome == .failed(
            reason: "The agent exited with code 2.",
            lastOutput: "fatal: could not read config",
            tokenReport: TestDefaults.usage
        ))
    }

    /// An adapter that never launches still produces a record — the terminal
    /// state closest to "nothing happened" is still written.
    @Test("An agent that cannot launch is recorded as failed, exactly once")
    func failureToLaunchIsRecordedOnce() async {
        let writer = RecordingSessionRecordWriter()
        let adapter = UnlaunchableAgentAdapter()
        let pipeline = SessionPipeline(
            assembler: makeTestAssembler(),
            preCheck: FixedSafeguardsPreCheck(.approved),
            adapter: adapter,
            gate: RecordingSafeguardsGate(),
            decisionLog: RecordingGatedDecisionLog(),
            recordWriter: writer,
            memories: RecordingMemoriesUpdatePort()
        )

        let record = await pipeline.run(
            intent: makeTestIntent(),
            guideline: makeSessionGuideline(),
            safeguards: makeTestSafeguards(),
            connectors: makeTestConnectors(),
            launch: SessionLaunch(agentName: testAgentName, configuration: TestLaunch.configuration())
        )

        #expect(record.outcome == .failed(
            reason: "Install the agent CLI and put it on PATH.",
            tokenReport: UnlaunchableAgentAdapter.unavailableUsage
        ))
        #expect(await writer.written.count == 1)
        #expect(await adapter.stopCount == 1)
    }
}
