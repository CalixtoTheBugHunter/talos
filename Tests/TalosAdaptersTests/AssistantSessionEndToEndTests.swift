import Foundation
@testable import TalosAdapters
import TalosCore
import TalosOrchestration
import TalosProjectLibrary
import TalosSafeguards
import Testing

/// One project's worth of real Project Library documents, loaded from a real
/// temp `.talos/` tree the same way ``AssistantSessionComposer`` loads a
/// user's — ``GuidelineDocumentParser`` and ``SafeguardsLoader`` parsing real
/// files, never a hand-built ``GuidelineDocument``. `.talos/project.yaml`,
/// `agents.yaml`, and `connectors.yaml` are out of scope here: this fixture
/// exercises the pipeline directly, not the composition root that reads
/// those three (covered by `AssistantSessionComposerTests`, tracked
/// separately).
private struct AssistantEndToEndProject {
    let id = ProjectIdentifier.generate()
    let guideline: GuidelineDocument
    let safeguards: SafeguardsDocument
    let connectors = ConnectorsManifest()

    static func make() throws -> Self {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("talos-assistant-e2e-\(UUID().uuidString)", isDirectory: true)
        let guidelinesDirectory = root.appendingPathComponent(".talos/guidelines", isDirectory: true)
        try FileManager.default.createDirectory(at: guidelinesDirectory, withIntermediateDirectories: true)

        let safeguardsFile = root.appendingPathComponent(".talos/safeguards.md", isDirectory: false)
        try "# Project safeguards\n\nNo project-specific policy for this fixture.\n"
            .write(to: safeguardsFile, atomically: true, encoding: .utf8)

        let guidelineFile = guidelinesDirectory.appendingPathComponent("assistant.md", isDirectory: false)
        let guidelineContents = """
        ---
        purpose: >-
          Answer a question about this fixture project.
        context:
          - spec-drive
          - memories
        tokenCeiling: 4000
        outputExpectations: >-
          A short, cited answer.
        ---

        Notes are yours to add below this line.

        """
        try guidelineContents.write(to: guidelineFile, atomically: true, encoding: .utf8)

        let guideline = try GuidelineDocumentParser.parse(
            contents: String(contentsOf: guidelineFile, encoding: .utf8),
            subFunction: .assistant,
            file: guidelineFile.path
        )
        let safeguards = try SafeguardsLoader.load(projectRoot: root)
        return Self(guideline: guideline, safeguards: safeguards)
    }

    func intent(content: String) -> Intent {
        Intent(content: content, source: .userText, project: id, requestingSubFunction: .assistant)
    }
}

/// Records every prompt the gate presented — the read/write-tier assertion
/// this suite exists to make is entirely about how many times, and at which
/// tier, this is called.
private actor RecordingApprovalPrompt: SafeguardsApprovalPrompt {
    private(set) var presented: [(action: SafeguardsActionType, tier: SafeguardsTier)] = []
    private let outcome: AgentPermissionDecision

    init(outcome: AgentPermissionDecision) {
        self.outcome = outcome
    }

    func present(
        _: AgentPermissionRequest,
        action: SafeguardsActionType,
        tier: SafeguardsTier
    ) async -> AgentPermissionDecision? {
        presented.append((action, tier))
        return outcome
    }
}

private actor RecordingGatedDecisionLog: GatedDecisionLog {
    private(set) var entries: [GatedDecisionEntry] = []

    func record(_ entry: GatedDecisionEntry) async {
        entries.append(entry)
    }
}

/// Asserts Sub-function-Assistant#pipeline and #autonomy end to end, against
/// the real ``ClaudeCodeAdapter``, ``TieredSafeguardsGate``,
/// ``SafeguardsActionClassifier``, and ``ContextAssembler`` — only the
/// approval prompt and the decision log are test doubles, since what this
/// asserts is how many times and with what tier they were called. The
/// adapter runs against a fake `claude` executable and committed fixtures,
/// per "the suite installs nothing":
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-suite-installs-nothing
///
/// Claude Code's headless `-p` mode exits cleanly after every ordinary turn
/// without that exit signalling the *session* is over — `ClaudeCodeAdapter`
/// deliberately leaves its stream open on exit code 0, since an ordinary
/// turn and a deferred permission request both end that way. So each test
/// below stops the adapter itself once it has observed enough of the
/// transcript to assert against, exactly as a real Stop would.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree
@Suite("Assistant session, end to end")
struct AssistantSessionEndToEndTests {
    @Test("A full read-only Assistant session completes with no approval prompts")
    func readOnlySessionNeverPrompts() async throws {
        let project = try AssistantEndToEndProject.make()
        let executablePath = try ClaudeCodeFakeExecutable.write()
        let launch = SessionLaunch(
            agentName: "claude-code",
            configuration: ClaudeCodeFakeExecutable.configuration(
                launchResponse: ClaudeCodeFixture.path("tool-call.jsonl"),
                resumeResponse: ClaudeCodeFixture.path("tool-call.jsonl")
            )
        )
        let adapter = ClaudeCodeAdapter(executableOverride: executablePath)
        let approvalPrompt = RecordingApprovalPrompt(outcome: .allowed)
        let decisionLog = RecordingGatedDecisionLog()
        let pipeline = Self.makePipeline(adapter: adapter, approvalPrompt: approvalPrompt, decisionLog: decisionLog)

        let record = await pipeline.run(
            intent: project.intent(content: "What does the README say?"),
            guideline: project.guideline,
            safeguards: project.safeguards,
            connectors: project.connectors,
            launch: launch,
            observer: { event in
                guard case .toolCall = event else { return }
                Task { await adapter.stop() }
            }
        )

        guard case .stopped = record.outcome else {
            Issue.record("Expected a read-only turn to end stopped once observed, got \(record.outcome)")
            return
        }
        #expect(record.toolCallCount == 1)
        #expect(await approvalPrompt.presented.isEmpty)
        #expect(await decisionLog.entries.isEmpty)
        #expect(record.tokenOverheadRatio >= 0 && record.tokenOverheadRatio < 1)
        #expect(record.droppedContextParts.isEmpty)
    }

    @Test("A mutating tool call crosses into a gated tier, fires the gate, and the session continues")
    func mutationFiresTheGate() async throws {
        let project = try AssistantEndToEndProject.make()
        let executablePath = try ClaudeCodeFakeExecutable.write()
        let launch = SessionLaunch(
            agentName: "claude-code",
            configuration: ClaudeCodeFakeExecutable.configuration(
                launchResponse: ClaudeCodeFixture.path("both-together.jsonl"),
                resumeResponse: ClaudeCodeFixture.path("token-report.jsonl")
            )
        )
        let adapter = ClaudeCodeAdapter(executableOverride: executablePath)
        let approvalPrompt = RecordingApprovalPrompt(outcome: .denied)
        let decisionLog = RecordingGatedDecisionLog()
        let pipeline = Self.makePipeline(adapter: adapter, approvalPrompt: approvalPrompt, decisionLog: decisionLog)

        let record = await pipeline.run(
            intent: project.intent(content: "Write a note for me."),
            guideline: project.guideline,
            safeguards: project.safeguards,
            connectors: project.connectors,
            launch: launch,
            observer: { event in
                // The resumed turn's own output, reached only once the
                // denial was carried back and the agent continued — "a
                // denial is a normal outcome... the agent is told it was
                // denied and continues."
                guard case let .output(chunk) = event, chunk.text.contains("pong") else { return }
                Task { await adapter.stop() }
            }
        )

        guard case .stopped = record.outcome else {
            Issue.record("Expected the resumed turn to end stopped once observed, got \(record.outcome)")
            return
        }
        #expect(record.toolCallCount == 1)
        #expect(record.denialCount == 1)
        let presented = await approvalPrompt.presented
        #expect(presented.count == 1)
        // `ClaudeCodeAdapter` reports its own tool name ("Write") verbatim
        // rather than a taxonomy name — mapping one onto the other is
        // adapter-specific work tracked separately (Contributing § The
        // contract you implement; Decision Log 73). Until it lands, an
        // unrecognized name classifies at the *most* restrictive tier per
        // "classification defaults to the most restrictive tier when a call
        // is unrecognized" — so this mutation gates at irreversible today,
        // not write, and still correctly never falls through ungated.
        // https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#action-classification
        #expect(presented.first?.tier == .irreversible)
        let logged = await decisionLog.entries
        #expect(logged.map(\.outcome) == [.denied])
        #expect(logged.map(\.classification) == [.tier(.irreversible)])
    }

    private static func makePipeline(
        adapter: ClaudeCodeAdapter,
        approvalPrompt: RecordingApprovalPrompt,
        decisionLog: RecordingGatedDecisionLog
    ) -> SessionPipeline<AlwaysApprovedSafeguardsPreCheck, ClaudeCodeAdapter, TieredSafeguardsGate> {
        let allowlist = InMemoryEmptyAllowlist()
        let gate = TieredSafeguardsGate(allowlist: allowlist, approvalPrompt: approvalPrompt)
        let assembler = ContextAssembler(
            specDriveSource: InertContextSource.specDrive,
            boardSource: InertContextSource.board,
            memoriesSource: InertContextSource.memories
        )
        return SessionPipeline(
            assembler: assembler,
            preCheck: AlwaysApprovedSafeguardsPreCheck(),
            adapter: adapter,
            gate: gate,
            decisionLog: decisionLog,
            recordWriter: DiscardingSessionRecordWriter(),
            memories: NoOpSessionMemoriesUpdatePort()
        )
    }
}

/// Denies every write-tier action outright, standing in for
/// ``AllowlistStore`` here since none of this suite's assertions concern
/// what is or is not allowlisted — only that a mutation reaches the prompt at
/// all.
private struct InMemoryEmptyAllowlist: SafeguardsAllowlist {
    func isAllowlisted(_: SafeguardsActionType, project _: ProjectIdentifier) async -> Bool {
        false
    }
}

private struct DiscardingSessionRecordWriter: SessionRecordWriter {
    func write(_: SessionRecord) async {
        // Discarded — this suite asserts against the gate and the decision
        // log, never the stored record.
    }
}
