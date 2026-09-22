import TalosAdapters
import TalosCore
import TalosProjectLibrary
import TalosSafeguards
import Testing

/// An allowlist with a fixed answer, recording every action it was asked about.
private actor FixedAllowlist: SafeguardsAllowlist {
    private let answer: Bool
    private(set) var checked: [(action: SafeguardsActionType, project: ProjectIdentifier)] = []

    init(_ answer: Bool) {
        self.answer = answer
    }

    func isAllowlisted(_ action: SafeguardsActionType, project: ProjectIdentifier) async -> Bool {
        checked.append((action, project))
        return answer
    }
}

/// A prompt with a fixed answer, recording every request it was asked to present.
private actor FixedPrompt: SafeguardsApprovalPrompt {
    private let answer: AgentPermissionDecision?
    private(set) var presented: [AgentPermissionRequest] = []

    init(_ answer: AgentPermissionDecision?) {
        self.answer = answer
    }

    func present(
        _ request: AgentPermissionRequest,
        action _: SafeguardsActionType,
        tier _: SafeguardsTier
    ) async -> AgentPermissionDecision? {
        presented.append(request)
        return answer
    }
}

private let testProject = ProjectIdentifier(rawValue: "p-1")

/// The gate reads the taxonomy type the adapter classified rather than the
/// provider tool name — decision 96, foundational.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions
/// A board write reaches its write tier instead of the irreversible default a
/// raw tool name falls to, an unclassified call still falls to that default,
/// and a `classifiedAction` never lowers the never-allowlistable undeclared path.
@Suite("Tiered Safeguards gate: the adapter's classified action")
struct TieredSafeguardsGateClassifiedTests {
    private func classifiedRequest(
        _ action: SafeguardsActionType,
        toolName: String? = "projects_write",
        connectorAccess: AgentConnectorAccess? = nil
    ) -> AgentPermissionRequest {
        AgentPermissionRequest(
            id: "r1",
            prompt: "board write",
            toolName: toolName,
            connectorAccess: connectorAccess,
            classifiedAction: action
        )
    }

    @Test("A classified board.item.create is write tier and consults the allowlist")
    func classifiedCreateIsWriteTier() async {
        let allowlist = FixedAllowlist(false)
        let prompt = FixedPrompt(.allowed)
        let gate = TieredSafeguardsGate(allowlist: allowlist, approvalPrompt: prompt)

        let decision = await gate.decide(
            classifiedRequest(.boardItemCreate), project: testProject, subFunction: .automator
        )

        #expect(decision.action == .boardItemCreate)
        #expect(decision.classification == .tier(.write))
        #expect(await allowlist.checked.map(\.action) == [.boardItemCreate])
        #expect(await prompt.presented.count == 1)
    }

    @Test("A classified board.item.move is write tier")
    func classifiedMoveIsWriteTier() async {
        let gate = TieredSafeguardsGate(allowlist: FixedAllowlist(false), approvalPrompt: FixedPrompt(.denied))

        let decision = await gate.decide(
            classifiedRequest(.boardItemMove), project: testProject, subFunction: .automator
        )

        #expect(decision.action == .boardItemMove)
        #expect(decision.classification == .tier(.write))
    }

    /// The classified type wins over the raw provider tool name, which is not a
    /// taxonomy name and would otherwise fall to the irreversible default.
    @Test("The classified action is read in preference to the provider tool name")
    func classifiedActionWinsOverToolName() async {
        let gate = TieredSafeguardsGate(allowlist: FixedAllowlist(false), approvalPrompt: FixedPrompt(.denied))

        let decision = await gate.decide(
            classifiedRequest(.boardItemCreate, toolName: "projects_write"),
            project: testProject,
            subFunction: .automator
        )

        #expect(decision.action == .boardItemCreate)
        #expect(decision.classification == .tier(.write))
    }

    /// The safeguards invariant: a `connectorAccess` against an undeclared
    /// system resolves first, so a `classifiedAction` cannot downgrade the
    /// never-allowlistable irreversible path to an allowlistable write.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable
    @Test("A classified action cannot lower an undeclared connector access below irreversible")
    func classifiedActionCannotLowerUndeclaredAccess() async {
        let allowlist = FixedAllowlist(true)
        let prompt = FixedPrompt(.denied)
        let gate = TieredSafeguardsGate(
            allowlist: allowlist, approvalPrompt: prompt, connectors: ConnectorsManifest()
        )

        let decision = await gate.decide(
            classifiedRequest(
                .boardItemMove,
                connectorAccess: AgentConnectorAccess(target: "rogue", verb: .write)
            ),
            project: testProject,
            subFunction: .automator
        )

        #expect(decision.action == .connectorUndeclared)
        #expect(decision.classification == .tier(.irreversible))
        #expect(await allowlist.checked.isEmpty)
    }

    /// A held call the adapter did not classify still falls to the
    /// most-restrictive tier — the classifier's safe default is preserved.
    @Test("An unclassified call with an unknown tool name still falls to irreversible")
    func unclassifiedCallFallsToIrreversible() async {
        let gate = TieredSafeguardsGate(allowlist: FixedAllowlist(true), approvalPrompt: FixedPrompt(.denied))

        let decision = await gate.decide(
            AgentPermissionRequest(id: "r1", prompt: "unknown", toolName: "projects_write"),
            project: testProject,
            subFunction: .automator
        )

        #expect(decision.classification == .tier(.irreversible))
    }
}
