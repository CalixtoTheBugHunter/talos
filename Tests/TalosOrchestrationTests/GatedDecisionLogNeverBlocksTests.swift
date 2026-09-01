import TalosAdapters
import TalosCore
@testable import TalosOrchestration
import TalosProjectLibrary
import TalosSafeguards
import Testing

/// "Log writes never block the gate decision path" — the agent is carried
/// its decision even while the log write for that same decision is still in
/// flight, so a slow or stalled store cannot add latency to what the agent is
/// holding for.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
@Suite("Gated decision log never blocks the decision path")
struct GatedDecisionLogNeverBlocksTests {
    @Test("The adapter is carried its decision before the log write for that decision finishes")
    func decisionIsCarriedBeforeTheLogWriteFinishes() async {
        let request = AgentPermissionRequest(id: "t1", prompt: "Write Secrets.swift", toolName: "file.write")
        let adapter = ScriptedAgentAdapter(events: [
            .permissionRequest(request),
            terminated(.exited(code: 0))
        ])
        let gate = RecordingSafeguardsGate(
            .denied,
            action: TestDefaults.action,
            classification: .tier(.write),
            decidedBy: .user
        )
        let log = SuspendingGatedDecisionLog()
        let pipeline = makeTestPipeline(adapter: adapter, gate: gate, decisionLog: log)

        let runTask = Task { await runTestSession(pipeline) }

        // Waits for the write to actually start rather than sleeping a fixed
        // duration — the write is suspended on `log.release()` past this
        // point, so anything observed now happened strictly before it could
        // have finished.
        var writesStarted = log.writeStarted.makeAsyncIterator()
        await writesStarted.next()

        #expect(await adapter.carriedDecisions[request.id] == .denied)
        #expect(await log.entries.isEmpty)

        await log.release()
        _ = await runTask.value
        #expect(await log.entries.map(\.outcome) == [.denied])
    }
}

/// A ``GatedDecisionLog`` whose write suspends until ``release()`` is called,
/// announcing on ``writeStarted`` the instant it does — the same technique
/// `BlockingSafeguardsGate` uses to let a test observe "in flight" rather
/// than guess at it with a sleep.
private actor SuspendingGatedDecisionLog: GatedDecisionLog {
    nonisolated let writeStarted: AsyncStream<Void>
    private nonisolated let arrival: AsyncStream<Void>.Continuation
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private(set) var entries: [GatedDecisionEntry] = []

    init() {
        (writeStarted, arrival) = AsyncStream<Void>.makeStream()
    }

    func record(_ entry: GatedDecisionEntry) async {
        arrival.yield()
        if !released {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waiters.append(continuation)
            }
        }
        entries.append(entry)
    }

    func release() {
        released = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}
