import TalosAdapters
import TalosCore
import TalosProjectLibrary
import TalosSafeguards
import Testing

/// An allowlist with a fixed answer, recording every action and project it
/// was asked about.
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

/// A prompt with a fixed answer, recording every request it was asked to
/// present. `nil` models presentation or reachability failure.
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

private func makeRequest(toolName: String?) -> AgentPermissionRequest {
    AgentPermissionRequest(id: "r1", prompt: "do the thing", toolName: toolName)
}

private func decide(_ gate: TieredSafeguardsGate, toolName: String?) async -> SafeguardsDecision {
    await gate.decide(makeRequest(toolName: toolName), project: testProject, subFunction: .automator)
}

@Suite("Tiered Safeguards gate: refused types never reach a prompt")
struct TieredSafeguardsGateRefusedTests {
    @Test("config.safeguards.write is denied, attributed to Talos, without presenting a prompt")
    func configSafeguardsWrite() async {
        let prompt = FixedPrompt(.allowed)
        let gate = TieredSafeguardsGate(allowlist: FixedAllowlist(true), approvalPrompt: prompt)

        let decision = await decide(gate, toolName: "config.safeguards.write")

        #expect(decision.outcome == .denied)
        #expect(decision.classification == .refused)
        #expect(decision.actor == .talos)
        #expect(await prompt.presented.isEmpty)
    }

    @Test("config.allowlist.write is refused even when the allowlist would have said yes")
    func configAllowlistWrite() async {
        let allowlist = FixedAllowlist(true)
        let prompt = FixedPrompt(.allowed)
        let gate = TieredSafeguardsGate(allowlist: allowlist, approvalPrompt: prompt)

        let decision = await decide(gate, toolName: "config.allowlist.write")

        #expect(decision.classification == .refused)
        #expect(decision.outcome == .denied)
        #expect(await prompt.presented.isEmpty)
    }

    @Test("config.tier.write is refused")
    func configTierWrite() async {
        let prompt = FixedPrompt(.allowed)
        let gate = TieredSafeguardsGate(allowlist: FixedAllowlist(false), approvalPrompt: prompt)

        let decision = await decide(gate, toolName: "config.tier.write")

        #expect(decision.classification == .refused)
        #expect(decision.outcome == .denied)
        #expect(decision.actor == .talos)
        #expect(await prompt.presented.isEmpty)
    }
}

@Suite("Tiered Safeguards gate: write tier consults the allowlist")
struct TieredSafeguardsGateWriteTierTests {
    @Test("An allowlisted write-tier action is allowed by the allowlist, without presenting a prompt")
    func allowlistedWriteIsAllowedWithoutAPrompt() async {
        let allowlist = FixedAllowlist(true)
        let prompt = FixedPrompt(.denied)
        let gate = TieredSafeguardsGate(allowlist: allowlist, approvalPrompt: prompt)

        let decision = await decide(gate, toolName: "file.write")

        #expect(decision.outcome == .allowed)
        #expect(decision.classification == .tier(.write))
        #expect(decision.actor == .allowlist)
        #expect(await prompt.presented.isEmpty)
        #expect(await allowlist.checked.map(\.action) == [.fileWrite])
    }

    @Test("A non-allowlisted write-tier action is prompted, and the user's approval is carried back")
    func nonAllowlistedWriteIsPromptedAndApproved() async {
        let request = makeRequest(toolName: "file.write")
        let prompt = FixedPrompt(.allowed)
        let gate = TieredSafeguardsGate(allowlist: FixedAllowlist(false), approvalPrompt: prompt)

        let decision = await gate.decide(request, project: testProject, subFunction: .automator)

        #expect(decision.outcome == .allowed)
        #expect(decision.classification == .tier(.write))
        #expect(decision.actor == .user)
        #expect(await prompt.presented == [request])
    }

    @Test("A non-allowlisted write-tier action the user denies is denied, attributed to the user")
    func nonAllowlistedWriteIsPromptedAndDenied() async {
        let gate = TieredSafeguardsGate(allowlist: FixedAllowlist(false), approvalPrompt: FixedPrompt(.denied))

        let decision = await decide(gate, toolName: "file.write")

        #expect(decision.outcome == .denied)
        #expect(decision.actor == .user)
    }
}

@Suite("Tiered Safeguards gate: irreversible tier always prompts and is never allowlistable")
struct TieredSafeguardsGateIrreversibleTests {
    @Test("An irreversible action always prompts, even when the allowlist would have said yes")
    func irreversibleAlwaysPromptsDespiteAnAllowlistHit() async {
        let allowlist = FixedAllowlist(true)
        let prompt = FixedPrompt(.denied)
        let gate = TieredSafeguardsGate(allowlist: allowlist, approvalPrompt: prompt)

        let decision = await decide(gate, toolName: "process.run")

        #expect(decision.classification == .tier(.irreversible))
        #expect(await prompt.presented.count == 1)
        #expect(await allowlist.checked.isEmpty)
    }

    @Test("An approved irreversible action is attributed to the user")
    func irreversibleApprovedIsAttributedToTheUser() async {
        let gate = TieredSafeguardsGate(allowlist: FixedAllowlist(false), approvalPrompt: FixedPrompt(.allowed))

        let decision = await decide(gate, toolName: "deploy.production")

        #expect(decision.outcome == .allowed)
        #expect(decision.actor == .user)
    }
}

@Suite("Tiered Safeguards gate: fails closed")
struct TieredSafeguardsGateFailClosedTests {
    /// "A gate that cannot obtain a decision denies." A `nil` from the prompt
    /// models both a UI failure and an unreachable user.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed
    @Test("A prompt that cannot be presented denies, attributed to Talos")
    func unpresentablePromptDeniesAsTalos() async {
        let gate = TieredSafeguardsGate(allowlist: FixedAllowlist(false), approvalPrompt: FixedPrompt(nil))

        let decision = await decide(gate, toolName: "file.write")

        #expect(decision.outcome == .denied)
        #expect(decision.actor == .talos)
    }

    @Test("An unreachable user on an irreversible action denies, attributed to Talos")
    func unreachableUserOnIrreversibleDeniesAsTalos() async {
        let gate = TieredSafeguardsGate(allowlist: FixedAllowlist(false), approvalPrompt: FixedPrompt(nil))

        let decision = await decide(gate, toolName: "git.push.force")

        #expect(decision.outcome == .denied)
        #expect(decision.classification == .tier(.irreversible))
        #expect(decision.actor == .talos)
    }
}

@Suite("Tiered Safeguards gate: unrecognized and read-tier actions")
struct TieredSafeguardsGateClassificationTests {
    /// "Classification defaults to the most restrictive tier when a call is
    /// unrecognized — never to read." A CLI's own tool name (e.g. "Bash") is
    /// not yet a taxonomy name, so it takes this path until an adapter maps
    /// it — the classifier's designed-for safe default.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#action-classification
    @Test("An unrecognized tool name is gated at the irreversible tier and prompts")
    func unrecognizedToolNamePromptsAtIrreversible() async {
        let prompt = FixedPrompt(.denied)
        let gate = TieredSafeguardsGate(allowlist: FixedAllowlist(true), approvalPrompt: prompt)

        let decision = await decide(gate, toolName: "Bash")

        #expect(decision.classification == .tier(.irreversible))
        #expect(await prompt.presented.count == 1)
    }

    @Test("No tool name at all is gated at the irreversible tier")
    func noToolNamePromptsAtIrreversible() async {
        let gate = TieredSafeguardsGate(allowlist: FixedAllowlist(true), approvalPrompt: FixedPrompt(.denied))

        let decision = await decide(gate, toolName: nil)

        #expect(decision.classification == .tier(.irreversible))
    }

    /// A held action classifying as read should not occur in practice — an
    /// adapter holds only mutating calls — but the gate still resolves it
    /// correctly rather than falling through to a prompt or a denial.
    @Test("A read-tier action is allowed by Talos without a prompt")
    func readTierIsAllowedWithoutAPrompt() async {
        let prompt = FixedPrompt(.denied)
        let gate = TieredSafeguardsGate(allowlist: FixedAllowlist(false), approvalPrompt: prompt)

        let decision = await decide(gate, toolName: "file.read")

        #expect(decision.outcome == .allowed)
        #expect(decision.classification == .tier(.read))
        #expect(decision.actor == .talos)
        #expect(await prompt.presented.isEmpty)
    }
}

/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy
@Suite("Tiered Safeguards gate: connector access resolves against connectors.yaml")
struct TieredSafeguardsGateConnectorTests {
    private func makeDeclared(_ name: String) -> ConnectorsManifest {
        ConnectorsManifest(connectors: [
            ConnectorDeclaration(name: name, kind: .repo, target: "https://example.com/\(name)", reachedVia: .mcp)
        ])
    }

    private func connectorRequest(target: String, verb: AgentConnectorVerb) -> AgentPermissionRequest {
        AgentPermissionRequest(
            id: "r1",
            prompt: "connector call",
            connectorAccess: AgentConnectorAccess(target: target, verb: verb)
        )
    }

    @Test("A connector write against an undeclared target is irreversible and never reaches the allowlist")
    func undeclaredConnectorWriteIsIrreversible() async {
        let allowlist = FixedAllowlist(true)
        let prompt = FixedPrompt(.denied)
        let gate = TieredSafeguardsGate(allowlist: allowlist, approvalPrompt: prompt, connectors: ConnectorsManifest())

        let decision = await gate.decide(
            connectorRequest(target: "github-repo", verb: .write), project: testProject, subFunction: .automator
        )

        #expect(decision.action == .connectorUndeclared)
        #expect(decision.classification == .tier(.irreversible))
        #expect(await prompt.presented.count == 1)
        #expect(await allowlist.checked.isEmpty)
    }

    @Test("A connector write against a declared target is write tier and consults the allowlist")
    func declaredConnectorWriteIsWriteTier() async {
        let allowlist = FixedAllowlist(true)
        let prompt = FixedPrompt(.denied)
        let gate = TieredSafeguardsGate(
            allowlist: allowlist, approvalPrompt: prompt, connectors: makeDeclared("github-repo")
        )

        let decision = await gate.decide(
            connectorRequest(target: "github-repo", verb: .write), project: testProject, subFunction: .automator
        )

        #expect(decision.action == .connectorWrite)
        #expect(decision.classification == .tier(.write))
        #expect(decision.outcome == .allowed)
        #expect(await allowlist.checked.map(\.action) == [.connectorWrite])
        #expect(await prompt.presented.isEmpty)
    }

    @Test("A connector read against a declared target is read tier")
    func declaredConnectorReadIsReadTier() async {
        let prompt = FixedPrompt(.denied)
        let gate = TieredSafeguardsGate(
            allowlist: FixedAllowlist(false), approvalPrompt: prompt, connectors: makeDeclared("ci")
        )

        let decision = await gate.decide(
            connectorRequest(target: "ci", verb: .read), project: testProject, subFunction: .automator
        )

        #expect(decision.action == .connectorRead)
        #expect(decision.classification == .tier(.read))
        #expect(decision.outcome == .allowed)
        #expect(await prompt.presented.isEmpty)
    }

    /// The same target and verb resolve to opposite outcomes depending only
    /// on which manifest the gate holds — proof the lookup happens against
    /// the live registry at decision time, not from a value cached on the
    /// request or guessed from `toolName`.
    @Test("The same target resolves declared or undeclared depending on the manifest, not on the request")
    func sameTargetResolvesAgainstTheLiveManifest() async {
        let request = connectorRequest(target: "ci", verb: .read)
        let undeclaredGate = TieredSafeguardsGate(
            allowlist: FixedAllowlist(false), approvalPrompt: FixedPrompt(.denied), connectors: ConnectorsManifest()
        )
        let declaredGate = TieredSafeguardsGate(
            allowlist: FixedAllowlist(false), approvalPrompt: FixedPrompt(.denied), connectors: makeDeclared("ci")
        )

        let undeclaredDecision = await undeclaredGate.decide(request, project: testProject, subFunction: .automator)
        let declaredDecision = await declaredGate.decide(request, project: testProject, subFunction: .automator)

        #expect(undeclaredDecision.classification == .tier(.irreversible))
        #expect(declaredDecision.classification == .tier(.read))
    }
}
