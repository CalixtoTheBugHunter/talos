import Foundation
import TalosAdapters
import TalosCore
import TalosProjectLibrary
import TalosSafeguards

/// The assembled prompt text and the agent's stream of events, for a session
/// the pre-check approved.
public struct SafeguardsApproved: Sendable {
    public let intent: Intent
    public let context: AssembledContext

    /// The prompt sent to the agent: every included part in assembly order,
    /// then the intent's own text. Parts the assembler dropped are absent
    /// because they were dropped, not shortened. See ``PromptDataFraming``.
    public var prompt: AgentPrompt {
        let parts = PromptDataFraming.render(context.includedParts) + [intent.content]
        return AgentPrompt(text: parts.joined(separator: "\n\n"))
    }

    /// Stages 5-8: launches the agent, sends the prompt, streams output, routes
    /// every held action through `gate`, and writes each decision to
    /// `decisionLog` before carrying it back to the adapter. `sessionID` is
    /// minted once by the caller, not here, so every logged row shares the
    /// eventual session record's id; `now` timestamps each row.
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
        sessionID: UUID,
        launchConfiguration: AgentLaunchConfiguration,
        adapter: some AgentAdapter,
        gate: some SafeguardsGate,
        decisionLog: any GatedDecisionLog,
        now: @escaping @Sendable () -> Date = Date.init,
        observer: (@Sendable (AgentEvent) async -> Void)? = nil,
        tokenObserver: (@Sendable (SessionTokenUpdate) async -> Void)? = nil,
        onDenial: (@Sendable (SafeguardsActionType, String) async -> Void)? = nil
    ) async -> SessionRunOutcome {
        if Task.isCancelled {
            return await stop(adapter: adapter, metrics: SessionRunMetrics(), transcript: [])
        }

        let stream: AgentEventStream
        do {
            stream = try await adapter.launch(launchConfiguration)
            try await adapter.send(prompt)
        } catch {
            return await abandon(
                reason: launchFailureReason(error),
                adapter: adapter,
                metrics: SessionRunMetrics(),
                transcript: []
            )
        }

        let collaborators = SessionRunCollaborators(
            adapter: adapter,
            gate: gate,
            decisionLog: decisionLog,
            sessionID: sessionID,
            now: now,
            onDenial: onDenial
        )
        return await consume(stream, collaborators: collaborators, observer: observer, tokenObserver: tokenObserver)
    }

    /// Stages 6-8 over a launched agent's stream, ending on the first event
    /// that decides the session's outcome. Tallies ``SessionRunMetrics`` as
    /// events arrive: a `.toolCall` increments the tool-call count and, when
    /// its (name, targets) signature matches one already denied this session,
    /// the retry count — the concrete reading of "[the agent]... never retries
    /// the same denied action silently" available from the adapter contract.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
    private func consume(
        _ stream: AgentEventStream,
        collaborators: SessionRunCollaborators<some AgentAdapter, some SafeguardsGate>,
        observer: (@Sendable (AgentEvent) async -> Void)?,
        tokenObserver: (@Sendable (SessionTokenUpdate) async -> Void)?
    ) async -> SessionRunOutcome {
        // The last chunk only, never a buffer of the run: a crash has no
        // `AgentTermination` to carry the agent's own final words, and
        // retaining the stream would spend the active-memory budget on a
        // fast agent.
        var lastOutput = ""
        var metrics = SessionRunMetrics()
        var transcript: [SessionTranscriptEntry] = []
        var retries = RetryTracker()
        await reportTokenUsage(collaborators: collaborators, tokenObserver: tokenObserver)
        do {
            for try await event in stream {
                await observer?(event)
                await reportTokenUsage(collaborators: collaborators, tokenObserver: tokenObserver)
                switch event {
                case let .output(chunk):
                    lastOutput = chunk.text
                    transcript.append(.output(chunk.text))
                case let .toolCall(call):
                    note(call, metrics: &metrics, transcript: &transcript, retries: &retries)
                case let .permissionRequest(request):
                    if let stopped = try await carry(
                        request,
                        collaborators: collaborators,
                        metrics: &metrics,
                        retries: &retries,
                        transcript: transcript
                    ) {
                        return stopped
                    }
                case let .terminated(termination):
                    return await SessionRunOutcome(
                        outcome: outcome(for: termination, adapter: collaborators.adapter),
                        metrics: metrics,
                        transcript: transcript,
                        resumeToken: termination.resumeToken
                    )
                }
            }
        } catch {
            // The stream ended in an error rather than a `.terminated` event —
            // an agent crash. The session is failed, and still recorded.
            return await endWithoutTermination(
                reason: crashReason(error),
                lastOutput: lastOutput,
                adapter: collaborators.adapter,
                metrics: metrics,
                transcript: transcript
            )
        }

        // The stream finished without a `.terminated` event, which the adapter
        // contract says is always last. Treated as a crash for the same reason.
        return await endWithoutTermination(
            reason: "The agent stopped producing output without terminating.",
            lastOutput: lastOutput,
            adapter: collaborators.adapter,
            metrics: metrics,
            transcript: transcript
        )
    }

    /// Tallies a `.toolCall` into `metrics` and `transcript` — pulled out of
    /// `consume(_:collaborators:observer:tokenObserver:)`'s own switch only to
    /// keep that function under this module's `function_body_length` limit.
    private func note(
        _ call: AgentToolCall,
        metrics: inout SessionRunMetrics,
        transcript: inout [SessionTranscriptEntry],
        retries: inout RetryTracker
    ) {
        metrics.toolCallCount += 1
        if retries.noteToolCall(call) {
            metrics.retryCount += 1
        }
        transcript.append(.toolCall(id: call.id, name: call.name, targets: call.targets))
    }

    /// Gates one held action, logs the decision, tallies it into `metrics`,
    /// and carries it back to the agent. Returns non-`nil` only when the
    /// session was stopped while the prompt was pending: the decision is
    /// logged and tallied either way, and the agent it would have been told
    /// is about to be killed.
    ///
    /// The cancelled branch builds the outcome directly here rather than
    /// letting `consume(_:collaborators:observer:tokenObserver:)`'s own loop
    /// read a further event off `stream`: nothing guarantees the next
    /// buffered event is `adapter.stop()`'s own termination rather than
    /// something already queued ahead of it — a fake adapter that pre-yields
    /// its whole script at launch is one concrete case where it is not. So
    /// `resumeToken` is `nil` on this path even for an adapter that does have
    /// one, the same best-effort gap already accepted for `tokenUsage()` and
    /// `lastOutput` on every other degraded ending here.
    ///
    /// A request whose originating `.toolCall` signature was already denied
    /// this session is answered from `retries` without consulting `gate` —
    /// the gate would ask a user who already said no, which is the prompt
    /// the SPEC's "it never retries the same denied action silently" exists
    /// to prevent. A denial feeds `retries` the originating `.toolCall`'s
    /// signature, when one was observed, so a later `.toolCall` with the
    /// same signature is blocked the same way.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
    ///
    /// `onDenial` fires for every denial reaching this point, whether the
    /// gate was asked or the request was blocked without asking — the user
    /// is owed the same clear, non-alarming indication either way, since a
    /// blocked repeat is still a denial from their side of the gate.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#denial-is-not-failure
    private func carry(
        _ request: AgentPermissionRequest,
        collaborators: SessionRunCollaborators<some AgentAdapter, some SafeguardsGate>,
        metrics: inout SessionRunMetrics,
        retries: inout RetryTracker,
        transcript: [SessionTranscriptEntry]
    ) async throws -> SessionRunOutcome? {
        let decision = if let blocked = retries.blockedDecision(for: request.id) {
            blocked
        } else {
            await collaborators.gate.decide(
                request,
                project: intent.project,
                subFunction: intent.requestingSubFunction
            )
        }
        let entry = GatedDecisionEntry(
            project: intent.project,
            sessionID: collaborators.sessionID,
            timestamp: collaborators.now(),
            subFunction: intent.requestingSubFunction,
            request: request,
            decision: decision
        )
        switch decision.outcome {
        case .allowed:
            metrics.approvalCount += 1
        case .denied:
            metrics.denialCount += 1
            retries.noteDenial(of: request.id, action: decision.action, classification: decision.classification)
            await collaborators.onDenial?(decision.action, request.prompt)
        }
        if Task.isCancelled {
            await collaborators.decisionLog.record(entry)
            return await stop(adapter: collaborators.adapter, metrics: metrics, transcript: transcript)
        }
        // Resolved before logged: a slow write never delays the agent's answer.
        try await collaborators.adapter.resolve(request.id, with: decision.outcome)
        await collaborators.decisionLog.record(entry)
        return nil
    }

    /// A stream that ended without the `.terminated` event the adapter contract
    /// promises. A stop that arrived while output was still streaming lands
    /// here too, and it is stopped rather than failed.
    private func endWithoutTermination(
        reason: String,
        lastOutput: String,
        adapter: some AgentAdapter,
        metrics: SessionRunMetrics,
        transcript: [SessionTranscriptEntry]
    ) async -> SessionRunOutcome {
        if Task.isCancelled {
            return await stop(adapter: adapter, metrics: metrics, transcript: transcript)
        }
        return await abandon(
            reason: reason,
            lastOutput: lastOutput,
            adapter: adapter,
            metrics: metrics,
            transcript: transcript
        )
    }

    /// Ends a session the user stopped, killing the agent before recording the
    /// outcome. Stopped, not failed — the user's own act is neither.
    ///
    /// `stop()` is awaited from an already-cancelled task deliberately: the
    /// adapter completes it regardless, because "a surviving child is a failed
    /// stop, not a partial one." Only reached once `stream` has already ended
    /// without a `.terminated` event of its own, so — unlike the cancellation
    /// ``carry(_:collaborators:metrics:retries:)`` handles mid-stream — there
    /// is no live loop left to hand a resume token to; `resumeToken` is `nil`
    /// here, the same best-effort gap ``abandon(reason:lastOutput:adapter:metrics:transcript:)``
    /// already accepts for `tokenUsage()`.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree
    private func stop(
        adapter: some AgentAdapter,
        metrics: SessionRunMetrics,
        transcript: [SessionTranscriptEntry]
    ) async -> SessionRunOutcome {
        await adapter.stop()
        return await SessionRunOutcome(
            outcome: .stopped(adapter.tokenUsage()),
            metrics: metrics,
            transcript: transcript
        )
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
        adapter: some AgentAdapter,
        metrics: SessionRunMetrics,
        transcript: [SessionTranscriptEntry]
    ) async -> SessionRunOutcome {
        await adapter.stop()
        let tokens = await adapter.tokenUsage()
        return SessionRunOutcome(
            outcome: .failed(reason: reason, lastOutput: lastOutput, tokenReport: tokens),
            metrics: metrics,
            transcript: transcript
        )
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
