import TalosAdapters
import TalosOrchestration
import TalosProjectLibrary
import TalosSafeguards
import Testing

/// The detect-and-ask resolver maps a board write's outcome onto whether it
/// proceeds — proceed when it is not a board write, the states agree, or the
/// user applies; abandon when the user keeps or opens, or the prompt could not
/// be presented (fail-closed, actor Talos).
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions
@Suite("Board conflict resolver")
struct BoardConflictResolverTests {
    private let manifest = BoardManifest(provider: .githubProjects, columns: [
        BoardColumnMapping(column: "Todo", state: .ready),
        BoardColumnMapping(column: "Done", state: .done)
    ])

    private func request() -> AgentPermissionRequest {
        AgentPermissionRequest(
            id: "m1",
            prompt: "update_project_item_field — PVTI_1, Done",
            toolName: "update_project_item_field",
            arguments: ["item_id": "PVTI_1", "status": "Done"]
        )
    }

    private func resolver(
        expected: [BoardItem],
        actual: [BoardItem],
        present: @escaping @Sendable (BoardConflictPresentation) async -> BoardConflictChoice?
    ) -> DetectAndAskBoardConflictResolver {
        DetectAndAskBoardConflictResolver(
            recognizer: BoardWriteRecognizer(provider: .githubProjects),
            check: BoardConflictCheck(manifest: manifest),
            expected: expected,
            fetchActual: { actual },
            present: present
        )
    }

    @Test("A request that is not a board write proceeds without reading the board or prompting")
    func nonBoardWriteProceeds() async {
        let resolver = DetectAndAskBoardConflictResolver(
            recognizer: BoardWriteRecognizer(provider: .githubProjects),
            check: BoardConflictCheck(manifest: manifest),
            expected: [],
            fetchActual: { Issue.record("actual should not be read"); return [] },
            present: { _ in Issue.record("must not prompt"); return nil }
        )
        let plain = AgentPermissionRequest(id: "f1", prompt: "write", toolName: "file.write", arguments: ["path": "A"])
        #expect(await resolver.resolve(plain) == .proceed)
    }

    @Test("Agreeing states proceed without prompting")
    func agreementProceeds() async {
        let item = [BoardItem(id: "PVTI_1", title: "Ship", column: "Todo")]
        let resolver = resolver(expected: item, actual: item) { _ in
            Issue.record("must not prompt when states agree")
            return nil
        }
        #expect(await resolver.resolve(request()) == .proceed)
    }

    @Test("A divergence the user applies proceeds")
    func applyProceeds() async {
        let resolver = resolver(
            expected: [BoardItem(id: "PVTI_1", title: "Ship", column: "Todo")],
            actual: [BoardItem(id: "PVTI_1", title: "Ship", column: "Done")]
        ) { _ in .applyMove }
        #expect(await resolver.resolve(request()) == .proceed)
    }

    @Test("Keeping the board's state abandons the write as the user")
    func keepAbandonsAsUser() async {
        let resolver = resolver(
            expected: [BoardItem(id: "PVTI_1", title: "Ship", column: "Todo")],
            actual: [BoardItem(id: "PVTI_1", title: "Ship", column: "Done")]
        ) { _ in .keepHumanState }
        #expect(await resolver.resolve(request()) == .abandon(actor: .user))
    }

    @Test("An unpresentable prompt abandons the write fail-closed, attributed to Talos")
    func unpresentableAbandonsAsTalos() async {
        let resolver = resolver(
            expected: [BoardItem(id: "PVTI_1", title: "Ship", column: "Todo")],
            actual: [BoardItem(id: "PVTI_1", title: "Ship", column: "Done")]
        ) { _ in nil }
        #expect(await resolver.resolve(request()) == .abandon(actor: .talos))
    }
}
