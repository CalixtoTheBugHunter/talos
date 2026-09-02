import TalosAdapters

/// An adapter that launches and then produces nothing further — no output,
/// no permission request, no termination — modelling an agent that is
/// silently running with nothing yet to report. `launched` fires once the
/// stream exists, so a test can cancel the session at exactly that point:
/// the state none of the other fakes reach, where the session is suspended
/// waiting on the *next* event rather than on a gate decision.
///
/// `stop()` behaves like a real adapter's: it ends the stream with
/// `.terminated(.stopped)`, so cancellation reaching this adapter is what
/// unblocks the pipeline's `for try await` — proving the guarantee holds
/// even when nothing was ever pending.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree
actor HangingAgentAdapter: AgentAdapter {
    private var usage: TokenReport
    private var continuation: AgentEventStream.Continuation?
    private var hasFinished = false

    nonisolated let launched: AsyncStream<Void>
    private nonisolated let arrival: AsyncStream<Void>.Continuation

    private(set) var stopCount = 0

    init(usage: TokenReport = TestDefaults.usage) {
        self.usage = usage
        (launched, arrival) = AsyncStream<Void>.makeStream()
    }

    func launch(_: AgentLaunchConfiguration) async throws -> AgentEventStream {
        let (stream, continuation) = AgentEventStream.makeStream()
        self.continuation = continuation
        arrival.yield()
        return stream
    }

    func send(_: AgentPrompt) async throws {
        // Nothing to record: no test using this fake sends a second turn.
    }

    func resolve(_: AgentPermissionRequest.ID, with _: AgentPermissionDecision) async throws {
        // Unreachable: this fake never raises a permission request.
    }

    func tokenUsage() async -> TokenReport {
        usage
    }

    func stop() async {
        stopCount += 1
        guard !hasFinished else { return }
        hasFinished = true
        continuation?.yield(.terminated(AgentTermination(reason: .stopped)))
        continuation?.finish()
    }
}
