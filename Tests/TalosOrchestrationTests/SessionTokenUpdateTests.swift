import TalosAdapters
import TalosCore
import TalosOrchestration
import TalosProjectLibrary
import Testing

/// Verifies the `tokenObserver` seam ``SafeguardsApproved/run`` and
/// ``SessionPipeline/run`` report through — the mechanism behind "Token usage
/// for the running session" and "the display does not poll; it updates on
/// adapter events".
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#nothing-polls
@Suite("Session token update")
struct SessionTokenUpdateTests {
    @Test("A tokenObserver fires once before the first event, so Loading has something to show")
    func firesOnceBeforeTheFirstEvent() async {
        let adapter = ScriptedAgentAdapter(events: [terminated(.exited(code: 0))], usageSequence: [])
        let pipeline = makeTestPipeline(adapter: adapter)
        let recorder = RecordingTokenObserver()

        _ = await runTestSession(pipeline, tokenObserver: { await recorder.record($0) })

        // One for the pre-loop report, one after the `.terminated` event.
        #expect(await recorder.updates.count == 2)
        #expect(await recorder.updates.first?.report == TestDefaults.usage)
    }

    @Test("A tokenObserver fires once per event, tracking the adapter's own live report")
    func firesOncePerEventTrackingTheLiveReport() async {
        let firstTurn = TokenReport.measured(TokenCounts(input: 10, output: 2), model: "test-model")
        let secondTurn = TokenReport.measured(TokenCounts(input: 30, output: 9), model: "test-model")
        let adapter = ScriptedAgentAdapter(
            events: [
                .output(AgentOutputChunk(channel: .standardOutput, text: "Working.")),
                .toolCall(AgentToolCall(id: "t1", name: "Read", targets: ["README.md"])),
                terminated(.exited(code: 0))
            ],
            usageSequence: [
                .unavailable(TokenUsageUnavailable(reason: .notReported)),
                firstTurn,
                firstTurn,
                secondTurn
            ]
        )
        let pipeline = makeTestPipeline(adapter: adapter)
        let recorder = RecordingTokenObserver()

        _ = await runTestSession(pipeline, tokenObserver: { await recorder.record($0) })

        #expect(await recorder.updates.map(\.report) == [
            .unavailable(TokenUsageUnavailable(reason: .notReported)),
            firstTurn,
            firstTurn,
            secondTurn
        ])
    }

    @Test("Every update's contextOverheadRatio matches the assembled context's own ratio")
    func contextOverheadRatioMatchesAssembledContext() async throws {
        let adapter = ScriptedAgentAdapter(events: [
            .output(AgentOutputChunk(channel: .standardOutput, text: "Working.")),
            terminated(.exited(code: 0))
        ])
        let pipeline = makeTestPipeline(adapter: adapter)
        let recorder = RecordingTokenObserver()

        let intent = makeTestIntent()
        _ = await runTestSession(pipeline, intent: intent, tokenObserver: { await recorder.record($0) })

        let expected = try #require(makeTestAssembler().assemble(ContextAssemblyInput(
            intent: intent,
            guideline: makeSessionGuideline(),
            safeguards: makeTestSafeguards(),
            connectors: makeTestConnectors()
        )).assembledContext)

        let ratios = await recorder.updates.map(\.contextOverheadRatio)
        #expect(!ratios.isEmpty)
        #expect(ratios.allSatisfy { $0 == expected.overheadRatio })
    }

    @Test("No tokenObserver call happens when the pre-check denies")
    func noCallWhenPreCheckDenies() async {
        let pipeline = makeTestPipeline(
            preCheck: FixedSafeguardsPreCheck(.denied(reason: "Production deploys need a human.")),
            adapter: ScriptedAgentAdapter(events: [terminated(.exited(code: 0))])
        )
        let recorder = RecordingTokenObserver()

        _ = await runTestSession(pipeline, tokenObserver: { await recorder.record($0) })

        #expect(await recorder.updates.isEmpty)
    }

    @Test("No tokenObserver call happens when context assembly fails")
    func noCallWhenContextAssemblyFails() async {
        let adapter = ScriptedAgentAdapter(events: [terminated(.exited(code: 0))])
        let pipeline = SessionPipeline(
            assembler: makeTestAssembler(),
            preCheck: FixedSafeguardsPreCheck(.approved),
            adapter: adapter,
            gate: RecordingSafeguardsGate(),
            decisionLog: RecordingGatedDecisionLog(),
            recordWriter: RecordingSessionRecordWriter(),
            memories: RecordingMemoriesUpdatePort()
        )
        let recorder = RecordingTokenObserver()

        _ = await pipeline.run(
            intent: makeTestIntent(),
            // A ceiling the two pinned parts alone cannot fit.
            guideline: makeTestGuideline(context: ["memories"], tokenCeiling: 1),
            safeguards: makeTestSafeguards(),
            connectors: makeTestConnectors(),
            launch: SessionLaunch(agentName: testAgentName, configuration: TestLaunch.configuration()),
            tokenObserver: { await recorder.record($0) }
        )

        #expect(await recorder.updates.isEmpty)
    }
}

/// Collects every ``SessionTokenUpdate`` a run reported, in order.
private actor RecordingTokenObserver {
    private(set) var updates: [SessionTokenUpdate] = []

    func record(_ update: SessionTokenUpdate) {
        updates.append(update)
    }
}

private extension ContextAssemblyResult {
    var assembledContext: AssembledContext? {
        guard case let .assembled(context) = self else { return nil }
        return context
    }
}
