import TalosAdapters
import TalosProjectLibrary
import TalosSafeguards

/// The assembled prompt text and the agent's stream of events, for a session
/// the pre-check approved.
public struct SafeguardsApproved: Sendable {
    public let intent: Intent
    public let context: AssembledContext

    /// The prompt sent to the agent: every included part in assembly order,
    /// then the intent's own text. Parts the assembler dropped are absent
    /// because they were dropped, not shortened.
    public var prompt: AgentPrompt {
        let parts = context.includedParts.map(\.text) + [intent.content]
        return AgentPrompt(text: parts.joined(separator: "\n\n"))
    }

    /// Stages 5-8: launches the agent, sends the prompt, streams output, routes
    /// every held action through `gate`, and writes each decision to
    /// `decisionLog` before carrying it back to the adapter.
    ///
    /// A tool call and a permission request stay two distinct events here, and
    /// the gate answers only the second: a `.permissionRequest` is an action
    /// the adapter is holding, while a `.toolCall` is the agent announcing one
    /// and reaches `observer` as the console event it is. Gating both would put
    /// two prompts and two log rows on the single action an adapter announces
    /// and then holds. Whether a mutating call is held is the adapter's
    /// obligation, because core cannot tell from a `.toolCall` alone — reading
    /// its tool name is exactly what no core reader may do.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
    ///
    /// A user stop arrives as cancellation of the task running this call, and
    /// it is honored at every suspension the session can be sitting at —
    /// including a pending prompt, which is where a session waits longest.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
    public func run(
        launchConfiguration: AgentLaunchConfiguration,
        adapter: some AgentAdapter,
        gate: some SafeguardsGate,
        decisionLog: any GatedDecisionLog,
        observer: (@Sendable (AgentEvent) async -> Void)? = nil
    ) async -> SessionOutcome {
        if Task.isCancelled {
            return await stop(adapter: adapter)
        }

        let stream: AgentEventStream
        do {
            stream = try await adapter.launch(launchConfiguration)
            try await adapter.send(prompt)
        } catch {
            return await abandon(reason: launchFailureReason(error), adapter: adapter)
        }

        return await consume(
            stream,
            adapter: adapter,
            gate: gate,
            decisionLog: decisionLog,
            observer: observer
        )
    }

    /// Stages 6-8 over a launched agent's stream, ending on the first event
    /// that decides the session's outcome.
    private func consume(
        _ stream: AgentEventStream,
        adapter: some AgentAdapter,
        gate: some SafeguardsGate,
        decisionLog: any GatedDecisionLog,
        observer: (@Sendable (AgentEvent) async -> Void)?
    ) async -> SessionOutcome {
        var lastOutput = ""
        do {
            for try await event in stream {
                await observer?(event)
                switch event {
                case let .output(chunk):
                    // The last chunk only, never a buffer of the run: a crash
                    // has no `AgentTermination` to carry the agent's own final
                    // words, and retaining the stream would spend the
                    // active-memory budget on a fast agent.
                    lastOutput = chunk.text
                case .toolCall:
                    continue
                case let .permissionRequest(request):
                    if let stopped = try await carry(
                        request,
                        through: gate,
                        to: adapter,
                        logging: decisionLog
                    ) {
                        return stopped
                    }
                case let .terminated(termination):
                    return await outcome(for: termination, adapter: adapter)
                }
            }
        } catch {
            // The stream ended in an error rather than a `.terminated` event —
            // an agent crash. The session is failed, and still recorded.
            return await endWithoutTermination(
                reason: crashReason(error),
                lastOutput: lastOutput,
                adapter: adapter
            )
        }

        // The stream finished without a `.terminated` event, which the adapter
        // contract says is always last. Treated as a crash for the same reason.
        return await endWithoutTermination(
            reason: "The agent stopped producing output without terminating.",
            lastOutput: lastOutput,
            adapter: adapter
        )
    }

    /// Gates one held action, logs the decision, and carries it back to the
    /// agent. Returns non-`nil` only when the session was stopped while the
    /// prompt was pending: the decision is logged either way, and the agent it
    /// would have been told is about to be killed.
    private func carry(
        _ request: AgentPermissionRequest,
        through gate: some SafeguardsGate,
        to adapter: some AgentAdapter,
        logging decisionLog: any GatedDecisionLog
    ) async throws -> SessionOutcome? {
        let decision = await gate.decide(
            request,
            project: intent.project,
            subFunction: intent.requestingSubFunction
        )
        await decisionLog.record(GatedDecisionEntry(
            project: intent.project,
            subFunction: intent.requestingSubFunction,
            request: request,
            decision: decision
        ))
        if Task.isCancelled {
            return await stop(adapter: adapter)
        }
        try await adapter.resolve(request.id, with: decision.outcome)
        return nil
    }

    /// A stream that ended without the `.terminated` event the adapter contract
    /// promises. A stop that arrived while output was still streaming lands
    /// here too, and it is stopped rather than failed.
    private func endWithoutTermination(
        reason: String,
        lastOutput: String,
        adapter: some AgentAdapter
    ) async -> SessionOutcome {
        if Task.isCancelled {
            return await stop(adapter: adapter)
        }
        return await abandon(reason: reason, lastOutput: lastOutput, adapter: adapter)
    }

    /// Ends a session the user stopped, killing the agent before recording the
    /// outcome. Stopped, not failed — the user's own act is neither.
    ///
    /// `stop()` is awaited from an already-cancelled task deliberately: the
    /// adapter completes it regardless, because "a surviving child is a failed
    /// stop, not a partial one."
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree
    private func stop(adapter: some AgentAdapter) async -> SessionOutcome {
        await adapter.stop()
        return await .stopped(adapter.tokenUsage())
    }

    /// Ends a session that stopped without a `.terminated` event, killing the
    /// agent before recording the outcome.
    ///
    /// The `stop()` is the point: an agent left running past the session that
    /// owns it acts outside the gate. `stop()` is safe to call on an adapter
    /// that never launched or has already finished.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree
    private func abandon(
        reason: String,
        lastOutput: String = "",
        adapter: some AgentAdapter
    ) async -> SessionOutcome {
        await adapter.stop()
        return await .failed(reason: reason, lastOutput: lastOutput, tokenReport: adapter.tokenUsage())
    }

    private func outcome(
        for termination: AgentTermination,
        adapter: some AgentAdapter
    ) async -> SessionOutcome {
        let tokens = await adapter.tokenUsage()
        switch termination.reason {
        case .exited(0):
            // A clean exit is a success even when the gate denied along the
            // way: "a denial is a normal outcome. The agent is told it was
            // denied and continues" — and each denial is its own log entry, so
            // recording the session as denied would report the refusal of one
            // action as the outcome of the whole run.
            return .succeeded(tokens)
        case let .exited(code):
            return .failed(
                reason: "The agent exited with code \(code).",
                lastOutput: termination.lastOutput,
                tokenReport: tokens
            )
        case .stopped:
            return .stopped(tokens)
        case .denied:
            return .denied(tokens)
        case .failedToLaunch:
            return .failed(
                reason: "The agent could not be launched.",
                lastOutput: termination.lastOutput,
                tokenReport: tokens
            )
        }
    }

    private func launchFailureReason(_ error: any Error) -> String {
        (error as? AgentNotRunningError)?.fix ?? "The agent could not be launched."
    }

    private func crashReason(_ error: any Error) -> String {
        (error as? AgentNotRunningError)?.fix ?? "The agent stopped responding: \(error)."
    }
}
