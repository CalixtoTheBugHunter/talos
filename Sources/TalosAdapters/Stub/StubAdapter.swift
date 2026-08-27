import Foundation

/// A compile-only, in-memory conformance to ``AgentAdapter`` — no process, no
/// CLI, no PATH probe. It exists to prove
/// "**Adding an agent means writing one adapter, never touching Talos core**"
/// rather than to run a real agent.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#agent-adapters
///
/// **Read this before writing a Gemini CLI, Codex CLI, or Ollama-backed
/// adapter.** It is the reference contributors are pointed at by
/// § The easiest high-value contribution —
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing —
/// every one of the six capabilities is here, in the smallest shape that
/// discharges each, and this file imports nothing but `Foundation`. A second
/// adapter that needed a `TalosCore` type, a core-side name branch, or a
/// widened protocol would have found that need here first.
///
/// Driven entirely by whichever test holds it, through ``emit(_:)`` — there is
/// no child process to produce events on its own.
actor StubAdapter: AgentAdapter {
    private var continuation: AgentEventStream.Continuation?
    private var usage: TokenReport
    private var lastOutput = ""
    private var hasFinished = false
    private var openRequestIDs: Set<String> = []

    init(usage: TokenReport = .measured(TokenCounts(input: 0, output: 0), model: "stub-model")) {
        self.usage = usage
    }

    // MARK: - The six capabilities

    func launch(_: AgentLaunchConfiguration) async throws -> AgentEventStream {
        let (stream, continuation) = AgentEventStream.makeStream()
        self.continuation = continuation
        return stream
    }

    func send(_: AgentPrompt) async throws {
        guard continuation != nil, !hasFinished else {
            throw AgentNotRunningError(fix: "Launch the adapter before sending a prompt.")
        }
        // A real adapter would hand the prompt to its CLI here. The stub has
        // no CLI, so transporting it verbatim means nothing more than
        // accepting it without editing, summarizing, or appending to it.
    }

    func resolve(_ requestID: AgentPermissionRequest.ID, with _: AgentPermissionDecision) async throws {
        guard openRequestIDs.contains(requestID) else {
            throw AgentNotRunningError(fix: "No permission request '\(requestID)' is waiting for a decision.")
        }
        openRequestIDs.remove(requestID)
        // A real adapter would carry `decision` back to its CLI here. The gate
        // produced it; the stub, like any adapter, never originates one.
    }

    func tokenUsage() async -> TokenReport {
        usage
    }

    func stop() async {
        finish(AgentTermination(reason: .stopped, lastOutput: lastOutput))
    }

    // MARK: - Driving it from a test

    /// Emits `event` on the stream, in order, exactly as a real adapter's
    /// parse would. A `terminated` event ends the run.
    func emit(_ event: AgentEvent) {
        guard !hasFinished else { return }
        switch event {
        case let .output(chunk):
            lastOutput = chunk.text
        case .toolCall:
            break
        case let .permissionRequest(request):
            openRequestIDs.insert(request.id)
        case let .terminated(termination):
            finish(termination)
            return
        }
        continuation?.yield(event)
    }

    private func finish(_ termination: AgentTermination) {
        guard !hasFinished else { return }
        hasFinished = true
        continuation?.yield(.terminated(termination))
        continuation?.finish()
    }
}
