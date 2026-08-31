import TalosAdapters
import TalosProjectLibrary
import TalosSafeguards

/// Stage 1, `intent` — the only place a session can begin.
///
/// The eleven stages the types in this file model, in the order the SPEC fixes
/// them: `intent` → sub-function selects guideline set → Talos assembles
/// context from Project Library → Safeguards pre-check → agent adapter runs
/// the agent → stream output to console → each mutating tool call hits the
/// Safeguards gate → approve / deny → session record written → tokens +
/// outcome to Monitor Screen → memories updated.
///
/// Only this stage declares a `public init`. Every later one relies on the
/// memberwise initializer Swift synthesizes for a `public struct`, which is
/// `internal` — so outside this module the previous stage's transition method
/// is the only way to obtain one, and skipping the pre-check is a compile
/// error rather than a runtime rejection. Giving a later stage a `public init`
/// would undo that.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model
public struct IntentReceived: Sendable {
    public let intent: Intent

    public init(intent: Intent) {
        self.intent = intent
    }

    /// Stage 2, "sub-function selects guideline set".
    public func selectGuideline(_ guideline: GuidelineDocument) -> GuidelineSelected {
        GuidelineSelected(intent: intent, guideline: guideline)
    }
}

/// Stage 2, "sub-function selects guideline set".
public struct GuidelineSelected: Sendable {
    public let intent: Intent
    public let guideline: GuidelineDocument

    /// Stage 3, "Talos assembles context from Project Library". Delegates to
    /// ``ContextAssembler`` rather than re-implementing the ceiling rules.
    public func assembleContext(
        using assembler: ContextAssembler,
        safeguards: SafeguardsDocument,
        connectors: ConnectorsManifest
    ) -> ContextAssemblyStageOutcome {
        let input = ContextAssemblyInput(
            intent: intent,
            guideline: guideline,
            safeguards: safeguards,
            connectors: connectors
        )
        switch assembler.assemble(input) {
        case let .assembled(context):
            return .assembled(ContextAssembled(
                intent: intent,
                guideline: guideline,
                safeguards: safeguards,
                connectors: connectors,
                context: context
            ))
        case let .failed(failure):
            return .failed(failure)
        }
    }
}

/// What stage 3 produced. A failure carries no next stage, so assembly
/// overflow cannot continue into a launch.
public enum ContextAssemblyStageOutcome: Sendable {
    case assembled(ContextAssembled)
    case failed(ContextAssemblyFailure)
}

/// Stage 3, "Talos assembles context from Project Library".
public struct ContextAssembled: Sendable {
    public let intent: Intent
    public let guideline: GuidelineDocument
    public let safeguards: SafeguardsDocument
    public let connectors: ConnectorsManifest
    public let context: AssembledContext

    /// Stage 4, "Safeguards pre-check" — the only transition that can produce
    /// a ``SafeguardsApproved``, which is in turn the only stage that can
    /// launch an agent.
    public func runSafeguardsPreCheck(
        using preCheck: some SafeguardsPreCheck
    ) async -> SafeguardsPreCheckStageOutcome {
        let input = SafeguardsPreCheckInput(
            project: intent.project,
            subFunction: intent.requestingSubFunction,
            intentContent: intent.content,
            guideline: guideline,
            safeguards: safeguards,
            connectors: connectors
        )
        switch await preCheck.evaluate(input) {
        case .approved:
            return .approved(SafeguardsApproved(intent: intent, context: context))
        case let .denied(reason):
            return .denied(reason: reason)
        }
    }
}

/// What stage 4 produced. A denial carries no next stage.
public enum SafeguardsPreCheckStageOutcome: Sendable {
    case approved(SafeguardsApproved)
    case denied(reason: String)
}

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

    /// Stages 5-8: launches the agent, sends the prompt, streams output, and
    /// routes every permission request through `gate` before carrying the
    /// decision back to the adapter.
    ///
    /// A tool call and a permission request stay two distinct events here:
    /// `.toolCall` is forwarded to `observer` and never gated, `.permissionRequest`
    /// is always gated. Collapsing them would remove the gate.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
    public func run(
        launchConfiguration: AgentLaunchConfiguration,
        adapter: some AgentAdapter,
        gate: some SafeguardsGate,
        observer: (@Sendable (AgentEvent) async -> Void)? = nil
    ) async -> SessionOutcome {
        let stream: AgentEventStream
        do {
            stream = try await adapter.launch(launchConfiguration)
            try await adapter.send(prompt)
        } catch {
            return await abandon(reason: launchFailureReason(error), adapter: adapter)
        }

        var sawDenial = false
        do {
            for try await event in stream {
                await observer?(event)
                switch event {
                case .output, .toolCall:
                    continue
                case let .permissionRequest(request):
                    let decision = await gate.decide(
                        request,
                        project: intent.project,
                        subFunction: intent.requestingSubFunction
                    )
                    if decision == .denied {
                        sawDenial = true
                    }
                    try await adapter.resolve(request.id, with: decision)
                case let .terminated(termination):
                    return await outcome(for: termination, sawDenial: sawDenial, adapter: adapter)
                }
            }
        } catch {
            // The stream ended in an error rather than a `.terminated` event —
            // an agent crash. The session is failed, and still recorded.
            return await abandon(reason: crashReason(error), adapter: adapter)
        }

        // The stream finished without a `.terminated` event, which the adapter
        // contract says is always last. Treated as a crash for the same reason.
        return await abandon(reason: "The agent stopped producing output without terminating.", adapter: adapter)
    }

    /// Ends a session that stopped without a `.terminated` event, killing the
    /// agent before recording the outcome.
    ///
    /// The `stop()` is the point: an agent left running past the session that
    /// owns it acts outside the gate, and "a surviving child is a failed stop,
    /// not a partial one." `stop()` is safe to call on an adapter that never
    /// launched or has already finished.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree
    private func abandon(reason: String, adapter: some AgentAdapter) async -> SessionOutcome {
        await adapter.stop()
        return await .failed(reason: reason, tokenReport: adapter.tokenUsage())
    }

    private func outcome(
        for termination: AgentTermination,
        sawDenial: Bool,
        adapter: some AgentAdapter
    ) async -> SessionOutcome {
        let tokens = await adapter.tokenUsage()
        switch termination.reason {
        case .exited(0):
            // A clean exit after a denied request is a denied session, not a
            // failed one: the agent did what it was allowed to do and stopped.
            return sawDenial ? .denied(tokens) : .succeeded(tokens)
        case let .exited(code):
            return .failed(reason: "The agent exited with code \(code).", tokenReport: tokens)
        case .stopped:
            return .stopped(tokens)
        case .denied:
            return .denied(tokens)
        case .failedToLaunch:
            return .failed(reason: "The agent could not be launched.", tokenReport: tokens)
        }
    }

    private func launchFailureReason(_ error: any Error) -> String {
        (error as? AgentNotRunningError)?.fix ?? "The agent could not be launched."
    }

    private func crashReason(_ error: any Error) -> String {
        (error as? AgentNotRunningError)?.fix ?? "The agent stopped responding: \(error)."
    }
}

/// Drives one session through all eleven stages.
///
/// The single call site that writes the session record and updates memories,
/// which is what makes "every terminal state writes a session record exactly
/// once" hold: every branch below — including the two that never reach
/// ``SafeguardsApproved`` — leaves through ``finish(_:for:)``, and nothing
/// inside a stage writes a record of its own.
///
/// A `struct` holding only `Sendable` collaborators, so two sessions on
/// different projects are separate values sharing no mutable state.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model
public struct SessionPipeline<
    PreCheck: SafeguardsPreCheck,
    Adapter: AgentAdapter,
    Gate: SafeguardsGate
>: Sendable {
    private let assembler: ContextAssembler
    private let preCheck: PreCheck
    private let adapter: Adapter
    private let gate: Gate
    private let recordWriter: any SessionRecordWriter
    private let memories: any SessionMemoriesUpdatePort

    public init(
        assembler: ContextAssembler,
        preCheck: PreCheck,
        adapter: Adapter,
        gate: Gate,
        recordWriter: any SessionRecordWriter,
        memories: any SessionMemoriesUpdatePort
    ) {
        self.assembler = assembler
        self.preCheck = preCheck
        self.adapter = adapter
        self.gate = gate
        self.recordWriter = recordWriter
        self.memories = memories
    }

    public func run(
        intent: Intent,
        guideline: GuidelineDocument,
        safeguards: SafeguardsDocument,
        connectors: ConnectorsManifest,
        launchConfiguration: AgentLaunchConfiguration,
        observer: (@Sendable (AgentEvent) async -> Void)? = nil
    ) async -> SessionRecord {
        let selected = IntentReceived(intent: intent).selectGuideline(guideline)

        let assembled: ContextAssembled
        switch selected.assembleContext(using: assembler, safeguards: safeguards, connectors: connectors) {
        case let .assembled(stage):
            assembled = stage
        case let .failed(failure):
            return await finish(.contextAssemblyFailed(failure), for: intent)
        }

        let approved: SafeguardsApproved
        switch await assembled.runSafeguardsPreCheck(using: preCheck) {
        case let .approved(stage):
            approved = stage
        case let .denied(reason):
            return await finish(.safeguardsPreCheckDenied(reason: reason), for: intent)
        }

        let outcome = await approved.run(
            launchConfiguration: launchConfiguration,
            adapter: adapter,
            gate: gate,
            observer: observer
        )
        return await finish(outcome, for: intent)
    }

    /// Stages 9-11: writes the record, then updates memories. Stage 10
    /// ("tokens + outcome to Monitor Screen") is discharged by the record
    /// itself carrying both; the Monitor Screen that reads it is tracked
    /// separately.
    private func finish(_ outcome: SessionOutcome, for intent: Intent) async -> SessionRecord {
        let record = SessionRecord(
            project: intent.project,
            subFunction: intent.requestingSubFunction,
            outcome: outcome
        )
        await recordWriter.write(record)
        await memories.updateMemories(for: record)
        return record
    }
}
