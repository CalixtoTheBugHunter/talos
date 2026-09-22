import TalosAdapters
import TalosCore
import TalosProjectLibrary
import TalosSafeguards
import Testing

private let gitTestProject = ProjectIdentifier(rawValue: "p-git")

/// A recording allowlist with a fixed answer, so a test can assert whether the
/// gate consulted it at all.
private actor RecordingAllowlist: SafeguardsAllowlist {
    private let answer: Bool
    private(set) var checked: [SafeguardsActionType] = []

    init(_ answer: Bool) {
        self.answer = answer
    }

    func isAllowlisted(_ action: SafeguardsActionType, project _: ProjectIdentifier) async -> Bool {
        checked.append(action)
        return answer
    }
}

private actor RecordingPrompt: SafeguardsApprovalPrompt {
    private let answer: AgentPermissionDecision?
    private(set) var presentedCount = 0

    init(_ answer: AgentPermissionDecision?) {
        self.answer = answer
    }

    func present(
        _: AgentPermissionRequest, action _: SafeguardsActionType, tier _: SafeguardsTier
    ) async -> AgentPermissionDecision? {
        presentedCount += 1
        return answer
    }
}

/// A git operation reaching a repo remote resolves to its specific taxonomy
/// type when the repo is declared and to `connector.undeclared` when it is not,
/// so a `git.push` is allowlistable against a declared repo and never against an
/// undeclared one — the never-allowlistable undeclared row.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable
@Suite("Tiered Safeguards gate: git repo-remote access resolves against connectors.yaml")
struct TieredSafeguardsGateGitRemoteTests {
    private func repoManifest() -> ConnectorsManifest {
        ConnectorsManifest(connectors: [
            ConnectorDeclaration(
                name: "github-repo", kind: .repo, target: "https://github.com/org/repo", reachedVia: .cli
            )
        ])
    }

    private func pushRequest(action: SafeguardsActionType, url: String = "") -> AgentPermissionRequest {
        AgentPermissionRequest(
            id: "r1",
            prompt: "git push",
            connectorAccess: AgentConnectorAccess(target: url, verb: .write, isRepoRemote: true),
            classifiedAction: action
        )
    }

    private func decide(_ gate: TieredSafeguardsGate, _ request: AgentPermissionRequest) async -> SafeguardsDecision {
        await gate.decide(request, project: gitTestProject, subFunction: .automator)
    }

    @Test("git.push to a declared repo is git.push, write tier, and consults the allowlist")
    func declaredPushIsGitPushWriteTier() async {
        let allowlist = RecordingAllowlist(true)
        let gate = TieredSafeguardsGate(
            allowlist: allowlist, approvalPrompt: RecordingPrompt(.denied), connectors: repoManifest()
        )

        let decision = await decide(gate, pushRequest(action: .gitPush))

        #expect(decision.action == .gitPush)
        #expect(decision.classification == .tier(.write))
        #expect(decision.outcome == .allowed)
        #expect(await allowlist.checked == [.gitPush])
    }

    /// AC6: a git operation reaching a remote not declared in `connectors.yaml`
    /// classifies as `connector.undeclared`, whatever the verb — here a bare
    /// `origin` push in a project that declares no repo connector.
    @Test("A push in a project with no declared repo is connector.undeclared and never allowlisted")
    func undeclaredRepoPushIsUndeclared() async {
        let allowlist = RecordingAllowlist(true)
        let prompt = RecordingPrompt(.denied)
        let gate = TieredSafeguardsGate(allowlist: allowlist, approvalPrompt: prompt, connectors: ConnectorsManifest())

        let decision = await decide(gate, pushRequest(action: .gitPush))

        #expect(decision.action == .connectorUndeclared)
        #expect(decision.classification == .tier(.irreversible))
        #expect(await allowlist.checked.isEmpty)
        #expect(await prompt.presentedCount == 1)
    }

    @Test("A push to an explicit URL matching a declared repo target is git.push")
    func explicitDeclaredURLIsGitPush() async {
        let gate = TieredSafeguardsGate(
            allowlist: RecordingAllowlist(true), approvalPrompt: RecordingPrompt(.denied), connectors: repoManifest()
        )

        let decision = await decide(gate, pushRequest(action: .gitPush, url: "git@github.com:org/repo.git"))

        #expect(decision.action == .gitPush)
        #expect(decision.classification == .tier(.write))
    }

    @Test("A push to an explicit URL matching no declared target is connector.undeclared")
    func explicitUndeclaredURLIsUndeclared() async {
        let gate = TieredSafeguardsGate(
            allowlist: RecordingAllowlist(true), approvalPrompt: RecordingPrompt(.denied), connectors: repoManifest()
        )

        let decision = await decide(gate, pushRequest(action: .gitPush, url: "https://gitlab.com/other/thing.git"))

        #expect(decision.action == .connectorUndeclared)
        #expect(decision.classification == .tier(.irreversible))
    }

    /// A declared repo never lowers a never-allowlistable git op: a force-push
    /// stays `git.push.force` at the irreversible tier, prompting rather than
    /// consulting the allowlist.
    @Test("git.push.force to a declared repo stays irreversible and never reaches the allowlist")
    func declaredForcePushStaysIrreversible() async {
        let allowlist = RecordingAllowlist(true)
        let prompt = RecordingPrompt(.denied)
        let gate = TieredSafeguardsGate(allowlist: allowlist, approvalPrompt: prompt, connectors: repoManifest())

        let decision = await decide(gate, pushRequest(action: .gitPushForce))

        #expect(decision.action == .gitPushForce)
        #expect(decision.classification == .tier(.irreversible))
        #expect(await allowlist.checked.isEmpty)
        #expect(await prompt.presentedCount == 1)
    }
}
