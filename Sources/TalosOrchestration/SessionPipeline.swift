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
    private let decisionLog: any GatedDecisionLog
    private let recordWriter: any SessionRecordWriter
    private let memories: any SessionMemoriesUpdatePort

    public init(
        assembler: ContextAssembler,
        preCheck: PreCheck,
        adapter: Adapter,
        gate: Gate,
        decisionLog: any GatedDecisionLog,
        recordWriter: any SessionRecordWriter,
        memories: any SessionMemoriesUpdatePort
    ) {
        self.assembler = assembler
        self.preCheck = preCheck
        self.adapter = adapter
        self.gate = gate
        self.decisionLog = decisionLog
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
            return await finish(
                .safeguardsPreCheckDenied(reason: reason),
                for: intent,
                context: assembled.context
            )
        }

        let outcome = await approved.run(
            launchConfiguration: launchConfiguration,
            adapter: adapter,
            gate: gate,
            decisionLog: decisionLog,
            observer: observer
        )
        return await finish(outcome, for: intent, context: approved.context)
    }

    /// Stages 9-11: writes the record, then updates memories. Stage 10
    /// ("tokens + outcome to Monitor Screen") is discharged by the record
    /// itself carrying both; the Monitor Screen that reads it is tracked
    /// separately.
    ///
    /// `context` is absent only where stage 3 produced none, which is the one
    /// case that has no dropped parts to report — it failed on the pinned parts
    /// alone.
    private func finish(
        _ outcome: SessionOutcome,
        for intent: Intent,
        context: AssembledContext? = nil
    ) async -> SessionRecord {
        let record = SessionRecord(
            project: intent.project,
            subFunction: intent.requestingSubFunction,
            outcome: outcome,
            droppedContextParts: context?.droppedParts ?? [],
            unavailableContextParts: context?.unavailableParts ?? []
        )
        await recordWriter.write(record)
        await memories.updateMemories(for: record)
        return record
    }
}
