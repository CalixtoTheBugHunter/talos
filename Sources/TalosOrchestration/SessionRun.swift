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
    /// because they were dropped, not shortened.
    public var prompt: AgentPrompt {
        let parts = context.includedParts.map(\.text) + [intent.content]
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
        onDenial: (@Sendable (SafeguardsActionType, String) async -> Void)? = nil
    ) async -> SessionRunOutcome {
        if Task.isCancelled {
            return await stop(adapter: adapter, metrics: SessionRunMetrics())
        }

        let stream: AgentEventStream
        do {
            stream = try await adapter.launch(launchConfiguration)
            try await adapter.send(prompt)
        } catch {
            return await abandon(
                reason: launchFailureReason(error),
                adapter: adapter,
                metrics: SessionRunMetrics()
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
        return await consume(stream, collaborators: collaborators, observer: observer)
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
        observer: (@Sendable (AgentEvent) async -> Void)?
    ) async -> SessionRunOutcome {
        var lastOutput = ""
        var metrics = SessionRunMetrics()
        var retries = RetryTracker()
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
                case let .toolCall(call):
                    metrics.toolCallCount += 1
                    if retries.noteToolCall(call) {
                        metrics.retryCount += 1
                    }
                case let .permissionRequest(request):
                    if let stopped = try await carry(
                        request,
                        collaborators: collaborators,
                        metrics: &metrics,
                        retries: &retries
                    ) {
                        return stopped
                    }
                case let .terminated(termination):
                    return await SessionRunOutcome(
                        outcome: outcome(for: termination, adapter: collaborators.adapter),
                        metrics: metrics
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
                metrics: metrics
            )
        }

        // The stream finished without a `.terminated` event, which the adapter
        // contract says is always last. Treated as a crash for the same reason.
        return await endWithoutTermination(
            reason: "The agent stopped producing output without terminating.",
            lastOutput: lastOutput,
            adapter: collaborators.adapter,
            metrics: metrics
        )
    }

    /// Gates one held action, logs the decision, tallies it into `metrics`,
    /// and carries it back to the agent. Returns non-`nil` only when the
    /// session was stopped while the prompt was pending: the decision is
    /// logged and tallied either way, and the agent it would have been told
    /// is about to be killed.
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
        retries: inout RetryTracker
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
            return await stop(adapter: collaborators.adapter, metrics: metrics)
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
        metrics: SessionRunMetrics
    ) async -> SessionRunOutcome {
        if Task.isCancelled {
            return await stop(adapter: adapter, metrics: metrics)
        }
        return await abandon(reason: reason, lastOutput: lastOutput, adapter: adapter, metrics: metrics)
    }

    /// Ends a session the user stopped, killing the agent before recording the
    /// outcome. Stopped, not failed — the user's own act is neither.
    ///
    /// `stop()` is awaited from an already-cancelled task deliberately: the
    /// adapter completes it regardless, because "a surviving child is a failed
    /// stop, not a partial one."
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree
    private func stop(adapter: some AgentAdapter, metrics: SessionRunMetrics) async -> SessionRunOutcome {
        await adapter.stop()
        return await SessionRunOutcome(outcome: .stopped(adapter.tokenUsage()), metrics: metrics)
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
        metrics: SessionRunMetrics
    ) async -> SessionRunOutcome {
        await adapter.stop()
        let tokens = await adapter.tokenUsage()
        return SessionRunOutcome(
            outcome: .failed(reason: reason, lastOutput: lastOutput, tokenReport: tokens),
            metrics: metrics
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

/// One tool call's identity for retry detection — the tool it named and the
/// targets it stated, exactly as the agent stated them. Two calls with this
/// pair equal are "the same action" for
/// ``SessionRunMetrics/retryCount``'s purposes.
private struct ToolCallSignature: Hashable, Sendable {
    let name: String
    let targets: [String]
}

/// Everything ``SafeguardsApproved/run(sessionID:launchConfiguration:adapter:gate:decisionLog:now:observer:onDenial:)``
/// needs to route one session, bundled so `consume`/`carry` take one
/// parameter for all six instead of six — the shape this module's own
/// `function_parameter_count` limit forces, and a reasonable one: the six
/// never vary independently within a single run.
private struct SessionRunCollaborators<Adapter: AgentAdapter, Gate: SafeguardsGate> {
    let adapter: Adapter
    let gate: Gate
    let decisionLog: any GatedDecisionLog
    let sessionID: UUID
    let now: @Sendable () -> Date
    let onDenial: (@Sendable (SafeguardsActionType, String) async -> Void)?
}

/// Tracks which tool-call signatures have been denied this session, so a
/// later `.toolCall` repeating one can be counted as a retry and a later
/// `.permissionRequest` repeating one can be blocked without asking again.
/// Two calls contribute to this: `noteToolCall` remembers a call's own
/// signature by its id, and `noteDenial` — given the id and decision a
/// `.permissionRequest` denial answers — promotes that remembered signature
/// into the denied set, carrying the decision's own action and
/// classification so a later block can log honestly without re-classifying.
private struct RetryTracker {
    private var signaturesByCallID: [String: ToolCallSignature] = [:]
    private var deniedSignatures: [ToolCallSignature: SafeguardsDecision] = [:]

    /// Records `call`'s signature and reports whether it repeats one already
    /// denied this session.
    mutating func noteToolCall(_ call: AgentToolCall) -> Bool {
        let signature = ToolCallSignature(name: call.name, targets: call.targets)
        signaturesByCallID[call.id] = signature
        return deniedSignatures.keys.contains(signature)
    }

    /// The permission request `requestID` was denied by `action`/`classification`.
    /// If it correlates to an observed `.toolCall` (the adapter contract does
    /// not guarantee one does), that call's signature is now a denied one.
    mutating func noteDenial(
        of requestID: String,
        action: SafeguardsActionType,
        classification: SafeguardsClassification
    ) {
        guard let signature = signaturesByCallID[requestID] else { return }
        deniedSignatures[signature] = SafeguardsDecision(
            outcome: .denied,
            action: action,
            classification: classification,
            actor: .talos
        )
    }

    /// A synthesized denial for `requestID`, if it correlates to a `.toolCall`
    /// signature already denied this session — the gate is not consulted for
    /// this decision, so the user is never asked about the same action twice.
    func blockedDecision(for requestID: String) -> SafeguardsDecision? {
        guard let signature = signaturesByCallID[requestID] else { return nil }
        return deniedSignatures[signature]
    }
}

/// What one session accumulated while stages 5-8 ran: tool calls observed,
/// gated decisions carried back, and retries of an already-denied action.
/// Zero for the two stages that never reach ``SafeguardsApproved`` at all —
/// a context-assembly failure or a pre-check denial has nothing here to
/// count.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen
public struct SessionRunMetrics: Equatable, Sendable {
    public var toolCallCount = 0
    public var approvalCount = 0
    public var denialCount = 0
    public var retryCount = 0

    public init(
        toolCallCount: Int = 0,
        approvalCount: Int = 0,
        denialCount: Int = 0,
        retryCount: Int = 0
    ) {
        self.toolCallCount = toolCallCount
        self.approvalCount = approvalCount
        self.denialCount = denialCount
        self.retryCount = retryCount
    }
}

/// What ``SafeguardsApproved/run(launchConfiguration:adapter:gate:decisionLog:observer:onDenial:)``
/// produces: the terminal ``SessionOutcome`` and the metrics accumulated
/// reaching it.
public struct SessionRunOutcome: Sendable {
    public let outcome: SessionOutcome
    public let metrics: SessionRunMetrics

    public init(outcome: SessionOutcome, metrics: SessionRunMetrics) {
        self.outcome = outcome
        self.metrics = metrics
    }
}
