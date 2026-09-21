import TalosAdapters
import TalosCore
import TalosOrchestration
import TalosProjectLibrary
import TalosSafeguards
import Testing

/// The fixtured end-to-end for decision 42's detect-and-ask across the gate
/// (decision 94): a real board move, allowed by the gate, whose item a human
/// changed since Talos read it. No installed CLI and no network — the adapter
/// is scripted and the out-of-band read is a closure — per decision 34.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#when-a-human-and-talos-move-the-same-item
@Suite("Board conflict, end to end")
struct BoardConflictSessionTests {
    private let manifest = BoardManifest(provider: .githubProjects, columns: [
        BoardColumnMapping(column: "Todo", state: .ready),
        BoardColumnMapping(column: "Done", state: .done)
    ])

    private func moveEvents() -> [AgentEvent] {
        [
            .toolCall(AgentToolCall(id: "m1", name: "projects_write", targets: ["PVTI_1", "update_project_item"])),
            .permissionRequest(AgentPermissionRequest(
                id: "m1",
                prompt: "projects_write update_project_item — PVTI_1, Done",
                toolName: "projects_write",
                arguments: ["method": "update_project_item", "item_id": "PVTI_1", "updated_field.value": "Done"]
            )),
            terminated(.exited(code: 0))
        ]
    }

    private func resolver(
        actual: [BoardItem],
        present: @escaping @Sendable (BoardConflictPresentation) async -> BoardConflictChoice?
    ) -> DetectAndAskBoardConflictResolver {
        DetectAndAskBoardConflictResolver(
            recognizer: BoardWriteRecognizer(provider: .githubProjects),
            check: BoardConflictCheck(manifest: manifest),
            expected: [BoardItem(id: "PVTI_1", title: "Ship", column: "Todo")],
            fetchActual: { actual },
            present: present
        )
    }

    @Test("A diverged board move is abandoned as denied: gate fired, agent told, session alive, user notified")
    func divergedMoveAbandonedCleanly() async {
        let adapter = ScriptedAgentAdapter(events: moveEvents())
        let gate = RecordingSafeguardsGate(
            .allowed, action: .boardItemMove, classification: .tier(.write), decidedBy: .user
        )
        let log = RecordingGatedDecisionLog()
        let notices = OnDenialSpy()
        let resolver = resolver(
            actual: [BoardItem(id: "PVTI_1", title: "Ship", column: "Done", updatedBy: "ada", updatedAt: "2026-09-21")],
            present: { _ in .keepHumanState }
        )
        let pipeline = makeTestPipeline(adapter: adapter, gate: gate, decisionLog: log)

        let record = await runTestSession(
            pipeline,
            onDenial: { action, _ in await notices.record(action) },
            boardConflict: resolver
        )

        // The gate fired on the move, and the session finished as an ordinary
        // successful run — a conflict abandon is a denial, not a failure.
        #expect(await gate.seenRequests.map(\.id) == ["m1"])
        #expect(record.outcome == .succeeded(TestDefaults.usage))
        // The agent was told the write was denied — nothing half-applied.
        #expect(await adapter.carriedDecisions == ["m1": .denied])
        // Recorded as denied, by the user, against the board move.
        #expect(record.denialCount == 1)
        #expect(await log.entries.map(\.outcome) == [.denied])
        #expect(await log.entries.map(\.actor) == [.user])
        #expect(await log.entries.first?.action == .boardItemMove)
        // The user was told, the same non-alarming path as any denial.
        #expect(await notices.actions == [.boardItemMove])
    }

    @Test("A board move whose state still agrees proceeds through the gate untouched")
    func agreeingMoveProceeds() async {
        let adapter = ScriptedAgentAdapter(events: moveEvents())
        let gate = RecordingSafeguardsGate(
            .allowed, action: .boardItemMove, classification: .tier(.write), decidedBy: .user
        )
        let log = RecordingGatedDecisionLog()
        let resolver = resolver(
            actual: [BoardItem(id: "PVTI_1", title: "Ship", column: "Todo")],
            present: { _ in Issue.record("must not prompt when the state still agrees"); return nil }
        )
        let pipeline = makeTestPipeline(adapter: adapter, gate: gate, decisionLog: log)

        let record = await runTestSession(pipeline, boardConflict: resolver)

        #expect(await adapter.carriedDecisions == ["m1": .allowed])
        #expect(record.denialCount == 0)
        #expect(await log.entries.map(\.outcome) == [.allowed])
    }
}

/// Records the actions `onDenial` was called with, so the user-facing half of a
/// clean abandon is asserted rather than assumed.
private actor OnDenialSpy {
    private(set) var actions: [SafeguardsActionType] = []

    func record(_ action: SafeguardsActionType) {
        actions.append(action)
    }
}
