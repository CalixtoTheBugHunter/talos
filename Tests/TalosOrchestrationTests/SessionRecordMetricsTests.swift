import Foundation
import TalosAdapters
import TalosOrchestration
import TalosProjectLibrary
import TalosSafeguards
import Testing

/// Asserts `SessionRecord`'s richer fields — duration, tool-call and
/// approval/denial/retry counts, and token overhead — against what actually
/// produced them, not against the implementation that happens to compute
/// them today.
@Suite("Session record metrics")
struct SessionRecordMetricsTests {
    /// AC1: "Every session writes exactly one record with project id,
    /// sub-function, agent, duration, and outcome." The agent name is not
    /// derivable from anything else the pipeline already carries — the
    /// caller supplies it, and it round-trips onto the record unchanged.
    @Test("The agent name the caller supplies reaches the record unchanged")
    func agentNameReachesTheRecord() async {
        let pipeline = makeTestPipeline(adapter: ScriptedAgentAdapter(events: [terminated(.exited(code: 0))]))

        let record = await runTestSession(pipeline, agentName: "claude-code-primary")

        #expect(record.agentName == "claude-code-primary")
    }

    /// AC3: "Tool-call count... [is] recorded." Every `.toolCall` on the
    /// stream is tallied, whether or not it is ever gated.
    @Test("Every tool call on the stream is counted")
    func toolCallsAreCounted() async {
        let adapter = ScriptedAgentAdapter(events: [
            .toolCall(AgentToolCall(id: "t1", name: "Read", targets: ["README.md"])),
            .toolCall(AgentToolCall(id: "t2", name: "Read", targets: ["Package.swift"])),
            terminated(.exited(code: 0))
        ])
        let pipeline = makeTestPipeline(adapter: adapter)

        let record = await runTestSession(pipeline)

        #expect(record.toolCallCount == 2)
    }

    /// AC3: "approval count, and denial count... are recorded." Every gated
    /// decision this session made is tallied, matching what
    /// `GatedDecisionLog` already records per decision.
    @Test("Approvals and denials are counted separately from each other")
    func approvalsAndDenialsAreCountedSeparately() async {
        let requests = [
            AgentPermissionRequest(id: "r1", prompt: "Write a.swift", toolName: "Write"),
            AgentPermissionRequest(id: "r2", prompt: "Write b.swift", toolName: "Write")
        ]
        let adapter = ScriptedAgentAdapter(events:
            requests.map { .permissionRequest($0) } + [terminated(.exited(code: 0))])
        // Denies the first request seen and allows every later one, so the
        // two counts land on different requests rather than both on one.
        let gate = SequencedSafeguardsGate(outcomes: [.denied, .allowed])
        let pipeline = makeTestPipeline(adapter: adapter, gate: gate)

        let record = await runTestSession(pipeline)

        #expect(record.approvalCount == 1)
        #expect(record.denialCount == 1)
    }

    /// AC3: "retry count... [is] recorded" — the concrete reading of "[the
    /// agent] never retries the same denied action silently": a `.toolCall`
    /// whose (name, targets) matches one already denied this session.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
    @Test("A tool call repeating a denied action's exact signature counts as a retry")
    func repeatingADeniedSignatureCountsAsARetry() async {
        let deniedCall = AgentToolCall(id: "t1", name: "Bash", targets: ["rm -rf /tmp/scratch"])
        let retryCall = AgentToolCall(id: "t2", name: "Bash", targets: ["rm -rf /tmp/scratch"])
        let adapter = ScriptedAgentAdapter(events: [
            .toolCall(deniedCall),
            .permissionRequest(AgentPermissionRequest(id: "t1", prompt: "Delete /tmp/scratch", toolName: "Bash")),
            .toolCall(retryCall),
            .permissionRequest(AgentPermissionRequest(id: "t2", prompt: "Delete /tmp/scratch", toolName: "Bash")),
            terminated(.exited(code: 0))
        ])
        let pipeline = makeTestPipeline(adapter: adapter, gate: RecordingSafeguardsGate(.denied))

        let record = await runTestSession(pipeline)

        #expect(record.toolCallCount == 2)
        #expect(record.denialCount == 2)
        #expect(record.retryCount == 1)
    }

    /// The counterpart to the test above: a tool call whose signature was
    /// never denied is not a retry, however many times it recurs.
    @Test("A tool call that was never denied is never counted as a retry")
    func aNeverDeniedSignatureIsNeverARetry() async {
        let call = AgentToolCall(id: "t1", name: "Read", targets: ["README.md"])
        let sameCallAgain = AgentToolCall(id: "t2", name: "Read", targets: ["README.md"])
        let adapter = ScriptedAgentAdapter(events: [
            .toolCall(call),
            .toolCall(sameCallAgain),
            terminated(.exited(code: 0))
        ])
        let pipeline = makeTestPipeline(adapter: adapter)

        let record = await runTestSession(pipeline)

        #expect(record.retryCount == 0)
    }

    /// AC4: "Talos-added token overhead is recorded per session" —
    /// `AssembledContext.overheadRatio` reaches the record unchanged.
    @Test("Token overhead on the record matches what stage 3 assembled")
    func tokenOverheadMatchesAssembledContext() async {
        let intent = makeTestIntent()
        let pipeline = makeTestPipeline(adapter: ScriptedAgentAdapter(events: [terminated(.exited(code: 0))]))

        let record = await runTestSession(pipeline, intent: intent)

        let input = ContextAssemblyInput(
            intent: intent,
            guideline: makeSessionGuideline(),
            safeguards: makeTestSafeguards(),
            connectors: makeTestConnectors()
        )
        guard case let .assembled(context) = makeTestAssembler().assemble(input) else {
            Issue.record("Expected the fixture guideline and safeguards to assemble")
            return
        }
        #expect(record.tokenOverheadRatio > 0)
        #expect(record.tokenOverheadRatio == context.overheadRatio)
    }

    /// A session that never assembles context added zero tokens — a fact,
    /// not a guess, per `SessionRecord.tokenOverheadRatio`'s own doc comment.
    @Test("A context-assembly failure records zero token overhead")
    func contextAssemblyFailureRecordsZeroOverhead() async {
        let pipeline = SessionPipeline(
            assembler: makeTestAssembler(),
            preCheck: FixedSafeguardsPreCheck(.approved),
            adapter: ScriptedAgentAdapter(events: [terminated(.exited(code: 0))]),
            gate: RecordingSafeguardsGate(),
            decisionLog: RecordingGatedDecisionLog(),
            recordWriter: RecordingSessionRecordWriter(),
            memories: RecordingMemoriesUpdatePort()
        )

        let record = await pipeline.run(
            intent: makeTestIntent(),
            guideline: makeTestGuideline(context: ["memories"], tokenCeiling: 1),
            safeguards: makeTestSafeguards(),
            connectors: makeTestConnectors(),
            launch: SessionLaunch(agentName: testAgentName, configuration: TestLaunch.configuration())
        )

        #expect(record.tokenOverheadRatio == 0)
    }

    /// AC1: "duration" is recorded — asserted with a real clock, since the
    /// shared test fixture pins one instant to keep unrelated tests'
    /// equality assertions meaningful.
    @Test("Duration reflects the time between the intent and the record")
    func durationReflectsElapsedTime() async {
        let clock = TickingTestClock()
        let pipeline = SessionPipeline(
            assembler: makeTestAssembler(),
            preCheck: FixedSafeguardsPreCheck(.approved),
            adapter: ScriptedAgentAdapter(events: [terminated(.exited(code: 0))]),
            gate: RecordingSafeguardsGate(),
            decisionLog: RecordingGatedDecisionLog(),
            recordWriter: RecordingSessionRecordWriter(),
            memories: RecordingMemoriesUpdatePort(),
            now: clock.next
        )

        let record = await pipeline.run(
            intent: makeTestIntent(),
            guideline: makeSessionGuideline(),
            safeguards: makeTestSafeguards(),
            connectors: makeTestConnectors(),
            launch: SessionLaunch(agentName: testAgentName, configuration: TestLaunch.configuration())
        )

        // Exactly two reads of `clock` happen per run — start and finish —
        // so this is the exact value, not just a positive one: it also
        // catches a regression that inflates duration by some other amount.
        #expect(record.duration == 1)
    }
}

/// A clock that advances by one second on every read, so
/// `durationReflectsElapsedTime` observes `now()` moving forward across the
/// two calls `SessionPipeline` makes per run — start and finish — without
/// `SessionPipeline`'s own `now` seam needing to be `async`.
private final class TickingTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 0)

    func next() -> Date {
        lock.lock()
        defer { lock.unlock() }
        let value = current
        current = current.addingTimeInterval(1)
        return value
    }
}

/// A gate that answers each request with the next outcome in a fixed
/// sequence, so a test can put an approval and a denial on two different
/// requests in one session rather than only ever repeating one decision.
private actor SequencedSafeguardsGate: SafeguardsGate {
    private var remaining: [AgentPermissionDecision]

    init(outcomes: [AgentPermissionDecision]) {
        remaining = outcomes
    }

    func decide(
        _: AgentPermissionRequest,
        project _: ProjectIdentifier,
        subFunction _: SubFunction
    ) async -> SafeguardsDecision {
        let outcome = remaining.isEmpty ? .allowed : remaining.removeFirst()
        return SafeguardsDecision(
            outcome: outcome,
            action: TestDefaults.action,
            tier: .write,
            actor: .user
        )
    }
}
