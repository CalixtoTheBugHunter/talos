import Foundation
import TalosAdapters
import TalosOrchestration
import TalosProjectLibrary
import TalosSafeguards

/// An ``AgentAdapter`` whose whole run is scripted up front: `launch` yields
/// every event in order and then ends the stream. Buffering means the pipeline
/// reads them in order regardless of when it starts consuming.
///
/// Mirrors `TalosAdaptersTests/FakeAdapter` rather than sharing it — a test
/// target cannot import another test target — and records what the pipeline
/// did so a test can assert on it.
actor ScriptedAgentAdapter: AgentAdapter {
    private let events: [AgentEvent]
    /// Set to end the stream by throwing instead of finishing — an agent crash.
    private let crash: (any Error)?
    /// Set to make carrying a decision back fail — the adapter broke between
    /// the gate deciding and the agent being told.
    private let resolveFailure: (any Error)?
    private var usage: TokenReport
    private var openRequests: Set<String> = []

    private(set) var launchCount = 0
    private(set) var sentPrompts: [AgentPrompt] = []
    /// The decisions the gate produced, carried back by request id.
    private(set) var carriedDecisions: [String: AgentPermissionDecision] = [:]
    private(set) var stopCount = 0

    init(
        events: [AgentEvent] = [],
        crash: (any Error)? = nil,
        resolveFailure: (any Error)? = nil,
        usage: TokenReport = TestDefaults.usage
    ) {
        self.events = events
        self.crash = crash
        self.resolveFailure = resolveFailure
        self.usage = usage
    }

    func launch(_: AgentLaunchConfiguration) async throws -> AgentEventStream {
        launchCount += 1
        let (stream, continuation) = AgentEventStream.makeStream()
        for event in events {
            if case let .permissionRequest(request) = event {
                openRequests.insert(request.id)
            }
            continuation.yield(event)
        }
        if let crash {
            continuation.finish(throwing: crash)
        } else {
            continuation.finish()
        }
        return stream
    }

    func send(_ prompt: AgentPrompt) async throws {
        sentPrompts.append(prompt)
    }

    func resolve(_ requestID: AgentPermissionRequest.ID, with decision: AgentPermissionDecision) async throws {
        if let resolveFailure {
            throw resolveFailure
        }
        guard openRequests.contains(requestID) else {
            throw AgentNotRunningError(fix: "No permission request '\(requestID)' is waiting for a decision.")
        }
        openRequests.remove(requestID)
        carriedDecisions[requestID] = decision
    }

    func tokenUsage() async -> TokenReport {
        usage
    }

    func stop() async {
        stopCount += 1
    }
}

/// An adapter that refuses to launch at all — the missing-CLI case. The four
/// capabilities below are unreachable once `launch` throws, so each is empty
/// rather than scripted.
actor UnlaunchableAgentAdapter: AgentAdapter {
    static let unavailableUsage = TokenReport.unavailable(
        TokenUsageUnavailable(reason: .notReported, agentVersion: nil)
    )

    private(set) var stopCount = 0

    func launch(_: AgentLaunchConfiguration) async throws -> AgentEventStream {
        throw AgentNotRunningError(fix: "Install the agent CLI and put it on PATH.")
    }

    func send(_: AgentPrompt) async throws {
        // Unreachable: nothing launched.
    }

    func resolve(_: AgentPermissionRequest.ID, with _: AgentPermissionDecision) async throws {
        // Unreachable: no request can arrive without a stream.
    }

    func tokenUsage() async -> TokenReport {
        Self.unavailableUsage
    }

    /// Reached, and harmless: the pipeline stops the agent on every abnormal
    /// exit rather than checking whether one was ever launched.
    func stop() async {
        stopCount += 1
    }
}

/// A pre-check with a fixed verdict, recording every input it judged so a test
/// can assert stage 4 saw the right project and sub-function.
final class FixedSafeguardsPreCheck: SafeguardsPreCheck, @unchecked Sendable {
    private let outcome: SafeguardsPreCheckOutcome
    private(set) var evaluatedInputs: [SafeguardsPreCheckInput] = []

    init(_ outcome: SafeguardsPreCheckOutcome = .approved) {
        self.outcome = outcome
    }

    func evaluate(_ input: SafeguardsPreCheckInput) async -> SafeguardsPreCheckOutcome {
        evaluatedInputs.append(input)
        return outcome
    }
}

/// A gate with a fixed decision, recording every request it was asked about.
actor RecordingSafeguardsGate: SafeguardsGate {
    private let decision: AgentPermissionDecision
    private(set) var seenRequests: [AgentPermissionRequest] = []
    private(set) var seenProjects: [ProjectIdentifier] = []

    init(_ decision: AgentPermissionDecision = .allowed) {
        self.decision = decision
    }

    func decide(
        _ request: AgentPermissionRequest,
        project: ProjectIdentifier,
        subFunction _: SubFunction
    ) async -> AgentPermissionDecision {
        seenRequests.append(request)
        seenProjects.append(project)
        return decision
    }
}

/// Counts writes, so "exactly once" is an assertion rather than an assumption.
actor RecordingSessionRecordWriter: SessionRecordWriter {
    private(set) var written: [SessionRecord] = []

    func write(_ record: SessionRecord) async {
        written.append(record)
    }
}

actor RecordingMemoriesUpdatePort: SessionMemoriesUpdatePort {
    private(set) var updated: [SessionRecord] = []

    func updateMemories(for record: SessionRecord) async {
        updated.append(record)
    }
}

/// Token figures for a scripted run, non-zero so a default report stays
/// distinguishable from an absent one.
enum TestDefaults {
    static let inputTokens = 120
    static let outputTokens = 45
    static let usage = TokenReport.measured(
        TokenCounts(input: inputTokens, output: outputTokens),
        model: "test-model"
    )
}

/// A working directory and environment for a scripted run. Deliberately holds
/// no credential of any kind.
enum TestLaunch {
    static func configuration() -> AgentLaunchConfiguration {
        AgentLaunchConfiguration(
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            environment: ["PATH": "/usr/bin:/bin"]
        )
    }
}

func makeTestConnectors() -> ConnectorsManifest {
    ConnectorsManifest()
}

/// Assembles a pipeline from the fakes above, with only the collaborators a
/// given test cares about named at the call site.
func makeTestPipeline(
    preCheck: FixedSafeguardsPreCheck = FixedSafeguardsPreCheck(),
    adapter: ScriptedAgentAdapter = ScriptedAgentAdapter(),
    gate: RecordingSafeguardsGate = RecordingSafeguardsGate(),
    recordWriter: RecordingSessionRecordWriter = RecordingSessionRecordWriter(),
    memories: RecordingMemoriesUpdatePort = RecordingMemoriesUpdatePort(),
    assembler: ContextAssembler = makeTestAssembler()
) -> SessionPipeline<FixedSafeguardsPreCheck, ScriptedAgentAdapter, RecordingSafeguardsGate> {
    SessionPipeline(
        assembler: assembler,
        preCheck: preCheck,
        adapter: adapter,
        gate: gate,
        recordWriter: recordWriter,
        memories: memories
    )
}

/// A `.terminated` event, which the adapter contract says is always the last
/// one on the stream.
func terminated(_ reason: AgentTerminationReason, lastOutput: String = "done") -> AgentEvent {
    .terminated(AgentTermination(reason: reason, lastOutput: lastOutput))
}

/// A ceiling generous enough that assembly never drops a part, so a test that
/// is not about overflow never trips it.
private let sessionTokenCeiling = 10000

func makeSessionGuideline() -> GuidelineDocument {
    makeTestGuideline(context: ["memories"], tokenCeiling: sessionTokenCeiling)
}

/// Runs one session with the fixture documents, shared by the pipeline suites.
func runTestSession(
    _ pipeline: SessionPipeline<FixedSafeguardsPreCheck, ScriptedAgentAdapter, RecordingSafeguardsGate>,
    intent: Intent = makeTestIntent(),
    observer: (@Sendable (AgentEvent) async -> Void)? = nil
) async -> SessionRecord {
    await pipeline.run(
        intent: intent,
        guideline: makeSessionGuideline(),
        safeguards: makeTestSafeguards(),
        connectors: makeTestConnectors(),
        launchConfiguration: TestLaunch.configuration(),
        observer: observer
    )
}
