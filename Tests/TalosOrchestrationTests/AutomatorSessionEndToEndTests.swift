import Foundation
import TalosAdapters
import TalosCore
import TalosOrchestration
import TalosProjectLibrary
import TalosSafeguards
import Testing

/// Records every prompt the gate presented and returns a scripted answer — the
/// write/irreversible-tier assertions this suite makes are entirely about how
/// many times, and at which tier, the gate reached the user.
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

/// Denies every write-tier action, standing in for an unconfigured project —
/// the deny-by-default starting point.
private struct EmptyAllowlist: SafeguardsAllowlist {
    func isAllowlisted(_: SafeguardsActionType, project _: ProjectIdentifier) async -> Bool {
        false
    }
}

/// Asserts Sub-function-Automator#autonomy and #pipeline end to end: Automator
/// enters the same shared pipeline Assistant does, and every mutating tool call
/// it attempts is held at the real ``TieredSafeguardsGate`` — write tier
/// deny-by-default, irreversible always prompting. Only the approval prompt and
/// the decision log are doubles, since what this asserts is how many times and
/// at what tier they were reached; the gate, classifier, allowlist, and context
/// assembler are real.
///
/// The write and irreversible tiers are reached through the connector-access
/// seam rather than a raw tool name: `AgentPermissionRequest.connectorAccess`
/// resolves to `connector.write` for a declared target and `connector.undeclared`
/// for an undeclared one, so a mutation classifies at a known tier without the
/// adapter-side tool-name → taxonomy mapping (Decision 73, tracked separately).
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy
@Suite("Automator session, end to end")
struct AutomatorSessionEndToEndTests {
    /// The taxonomy name a declared connector write resolves to — spelled as the
    /// taxonomy spells it, since it is the name a user writes into an allowlist.
    private static let connectorWrite = SafeguardsActionType(rawValue: "connector.write")

    /// The `automator.md` a real project gets, parsed by the real
    /// ``GuidelineDocumentParser`` rather than hand-built, so "loads and honors"
    /// is asserted against the file's own declared context list.
    private static func automatorGuideline() throws -> GuidelineDocument {
        let contents = """
        ---
        purpose: >-
          Carry out a requested change to this fixture project under the gate.
        context:
          - board
          - connectors
          - memories
        tokenCeiling: 4000
        outputExpectations: >-
          A short account of what changed.
        ---

        Automator acts under the Safeguards gate on every mutation.

        """
        return try GuidelineDocumentParser.parse(contents: contents, subFunction: .automator, file: "automator.md")
    }

    /// One declared connector, so a write against it resolves to write tier
    /// rather than the undeclared-target top tier.
    private static func declaredConnectors() -> ConnectorsManifest {
        ConnectorsManifest(connectors: [
            ConnectorDeclaration(name: "github", kind: .repo, target: "github.com/example/project", reachedVia: .cli)
        ])
    }

    private static func connectorRequest(
        id: String,
        target: String,
        verb: AgentConnectorVerb = .write
    ) -> AgentPermissionRequest {
        AgentPermissionRequest(
            id: id,
            prompt: "Automator wants to write \(target)",
            connectorAccess: AgentConnectorAccess(target: target, verb: verb)
        )
    }

    private func runAutomator(
        events: [AgentEvent],
        gate: TieredSafeguardsGate,
        decisionLog: RecordingGatedDecisionLog = RecordingGatedDecisionLog(),
        project: ProjectIdentifier = .generate(),
        guideline: GuidelineDocument,
        connectors: ConnectorsManifest = ConnectorsManifest(),
        assembler: ContextAssembler = makeTestAssembler(),
        onDenial: (@Sendable (SafeguardsActionType, String) async -> Void)? = nil
    ) async -> (record: SessionRecord, adapter: ScriptedAgentAdapter) {
        let adapter = ScriptedAgentAdapter(events: events)
        let pipeline = makeTestPipeline(adapter: adapter, gate: gate, decisionLog: decisionLog, assembler: assembler)
        let record = await pipeline.run(
            intent: makeTestIntent(
                content: "Move the board item to Done.",
                project: project,
                requestingSubFunction: .automator
            ),
            guideline: guideline,
            safeguards: makeTestSafeguards(),
            connectors: connectors,
            launch: SessionLaunch(agentName: testAgentName, configuration: TestLaunch.configuration()),
            onDenial: onDenial
        )
        return (record, adapter)
    }

    /// An `AllowlistStore` backed by a fresh temp `.talos/`, seeded with the
    /// given write-tier actions — the real store, so its refusal to hold an
    /// irreversible action is the real refusal.
    private func seededAllowlist(
        project: ProjectIdentifier,
        granting actions: [SafeguardsActionType] = []
    ) async throws -> AllowlistStore {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("talos-automator-allowlist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".talos", isDirectory: true), withIntermediateDirectories: true
        )
        let store = try AllowlistStore(projectRoot: root, project: project, changeLog: NoOpAllowlistChangeLog())
        for action in actions {
            try await store.allowlistAction(action, actor: "test-user")
        }
        return store
    }

    @Test("A read-only Automator session completes with no approval prompts")
    func readOnlySessionNeverPrompts() async throws {
        let approvalPrompt = RecordingApprovalPrompt(outcome: .allowed)
        let decisionLog = RecordingGatedDecisionLog()
        let gate = TieredSafeguardsGate(allowlist: EmptyAllowlist(), approvalPrompt: approvalPrompt)
        let (record, _) = try await runAutomator(
            events: [
                .toolCall(AgentToolCall(id: "t1", name: "Read", targets: ["README.md"])),
                terminated(.exited(code: 0))
            ],
            gate: gate,
            decisionLog: decisionLog,
            guideline: Self.automatorGuideline()
        )

        guard case .succeeded = record.outcome else {
            Issue.record("Expected a read-only Automator session to succeed, got \(record.outcome)")
            return
        }
        #expect(record.subFunction == .automator)
        #expect(record.toolCallCount == 1)
        #expect(await approvalPrompt.presented.isEmpty)
        #expect(await decisionLog.entries.isEmpty)
    }

    @Test("Every held mutating call reaches the gate, and a bare tool call does not")
    func everyMutatingCallHitsTheGate() async throws {
        let approvalPrompt = RecordingApprovalPrompt(outcome: .allowed)
        let decisionLog = RecordingGatedDecisionLog()
        let gate = TieredSafeguardsGate(
            allowlist: EmptyAllowlist(), approvalPrompt: approvalPrompt, connectors: Self.declaredConnectors()
        )
        let (record, _) = try await runAutomator(
            events: [
                .toolCall(AgentToolCall(id: "t0", name: "Read", targets: ["README.md"])),
                .permissionRequest(Self.connectorRequest(id: "w1", target: "github")),
                .permissionRequest(Self.connectorRequest(id: "w2", target: "github")),
                terminated(.exited(code: 0))
            ],
            gate: gate,
            decisionLog: decisionLog,
            guideline: Self.automatorGuideline()
        )

        guard case .succeeded = record.outcome else {
            Issue.record("Expected the session to succeed, got \(record.outcome)")
            return
        }
        // Both held mutating calls reached the gate; the announce-only tool call
        // did not — a tool call and a permission request are two events, and
        // only the second is gated.
        #expect(await decisionLog.entries.map(\.requestID) == ["w1", "w2"])
        #expect(await approvalPrompt.presented.count == 2)
        #expect(record.toolCallCount == 1)
    }

    @Test("A non-allowlisted write action prompts, is denied, and the session continues")
    func nonAllowlistedWriteActionPrompts() async throws {
        let approvalPrompt = RecordingApprovalPrompt(outcome: .denied)
        let decisionLog = RecordingGatedDecisionLog()
        let gate = TieredSafeguardsGate(
            allowlist: EmptyAllowlist(), approvalPrompt: approvalPrompt, connectors: Self.declaredConnectors()
        )
        let deniedActions = DeniedActionRecorder()
        let (record, _) = try await runAutomator(
            events: [
                .permissionRequest(Self.connectorRequest(id: "w1", target: "github")),
                terminated(.exited(code: 0))
            ],
            gate: gate,
            decisionLog: decisionLog,
            guideline: Self.automatorGuideline(),
            onDenial: { action, prompt in await deniedActions.record(action: action, prompt: prompt) }
        )

        // A denial is a normal outcome: the agent is told and the session
        // continues to its own clean exit.
        guard case .succeeded = record.outcome else {
            Issue.record("Expected the session to survive a denial, got \(record.outcome)")
            return
        }
        let presented = await approvalPrompt.presented
        #expect(presented.count == 1)
        #expect(presented.first?.action == Self.connectorWrite)
        #expect(presented.first?.tier == .write)
        #expect(record.denialCount == 1)
        let logged = await decisionLog.entries
        #expect(logged.map(\.outcome) == [.denied])
        #expect(logged.map(\.classification) == [.tier(.write)])
        #expect(logged.map(\.actor) == [.user])
        #expect(await deniedActions.actions == [Self.connectorWrite])
    }

    @Test("An allowlisted write action proceeds without prompting")
    func allowlistedWriteActionProceedsWithoutPrompting() async throws {
        let project = ProjectIdentifier.generate()
        let approvalPrompt = RecordingApprovalPrompt(outcome: .denied)
        let decisionLog = RecordingGatedDecisionLog()
        let allowlist = try await seededAllowlist(project: project, granting: [Self.connectorWrite])
        let gate = TieredSafeguardsGate(
            allowlist: allowlist, approvalPrompt: approvalPrompt, connectors: Self.declaredConnectors()
        )
        let (record, _) = try await runAutomator(
            events: [
                .permissionRequest(Self.connectorRequest(id: "w1", target: "github")),
                terminated(.exited(code: 0))
            ],
            gate: gate,
            decisionLog: decisionLog,
            project: project,
            guideline: Self.automatorGuideline()
        )

        guard case .succeeded = record.outcome else {
            Issue.record("Expected the allowlisted session to succeed, got \(record.outcome)")
            return
        }
        // Allowlisted: it never reached the prompt, and the decision names the
        // allowlist as the actor rather than the user.
        #expect(await approvalPrompt.presented.isEmpty)
        let logged = await decisionLog.entries
        #expect(logged.map(\.outcome) == [.allowed])
        #expect(logged.map(\.actor) == [.allowlist])
        #expect(record.approvalCount == 1)
    }

    @Test("An irreversible action always prompts, and can never be allowlisted")
    func irreversibleActionAlwaysPromptsEvenIfAllowlisted() async throws {
        let project = ProjectIdentifier.generate()
        let undeclared = SafeguardsActionType(rawValue: "connector.undeclared")
        // The store refuses to hold an irreversible action at all — "someone
        // tried to allowlist it" fails before any session runs.
        let allowlist = try await seededAllowlist(project: project, granting: [Self.connectorWrite])
        await #expect(throws: (any Error).self) {
            try await allowlist.allowlistAction(undeclared, actor: "test-user")
        }

        // And with a non-empty allowlist, an undeclared-target write still
        // prompts: the gate never consults the allowlist for the irreversible
        // tier.
        let approvalPrompt = RecordingApprovalPrompt(outcome: .allowed)
        let decisionLog = RecordingGatedDecisionLog()
        let gate = TieredSafeguardsGate(
            allowlist: allowlist, approvalPrompt: approvalPrompt, connectors: Self.declaredConnectors()
        )
        let (record, _) = try await runAutomator(
            events: [
                .permissionRequest(Self.connectorRequest(id: "x1", target: "rogue-service")),
                terminated(.exited(code: 0))
            ],
            gate: gate,
            decisionLog: decisionLog,
            project: project,
            guideline: Self.automatorGuideline()
        )

        guard case .succeeded = record.outcome else {
            Issue.record("Expected the session to succeed, got \(record.outcome)")
            return
        }
        let presented = await approvalPrompt.presented
        #expect(presented.count == 1)
        #expect(presented.first?.action == undeclared)
        #expect(presented.first?.tier == .irreversible)
        #expect(await decisionLog.entries.map(\.classification) == [.tier(.irreversible)])
    }

    @Test("The Automator session loads and honors automator.md's declared context")
    func loadsAndHonorsAutomatorGuideline() async throws {
        let approvalPrompt = RecordingApprovalPrompt(outcome: .allowed)
        let gate = TieredSafeguardsGate(allowlist: EmptyAllowlist(), approvalPrompt: approvalPrompt)
        // Every droppable source has content available; automator.md requests
        // board, connectors, and memories — but not spec-drive — so honoring the
        // guideline means the spec-drive excerpt is left out despite being
        // available.
        let (record, adapter) = try await runAutomator(
            events: [terminated(.exited(code: 0))],
            gate: gate,
            guideline: Self.automatorGuideline(),
            connectors: Self.declaredConnectors()
        )

        guard case .succeeded = record.outcome else {
            Issue.record("Expected the session to succeed, got \(record.outcome)")
            return
        }
        #expect(record.subFunction == .automator)
        let prompt = try #require(await adapter.sentPrompts.first).text
        #expect(prompt.contains("Automator acts under the Safeguards gate on every mutation."))
        #expect(prompt.contains("Board: 3 open items."))
        #expect(prompt.contains("Prefers dark mode."))
        #expect(prompt.contains("github"))
        #expect(!prompt.contains("Spec drive excerpt."))
    }
}

/// Records the actions the pipeline reported denied, so the denial-path
/// assertion sees what reached the caller `SessionComposer` wires to the denied
/// notice center.
private actor DeniedActionRecorder {
    private(set) var actions: [SafeguardsActionType] = []

    func record(action: SafeguardsActionType, prompt _: String) {
        actions.append(action)
    }
}
