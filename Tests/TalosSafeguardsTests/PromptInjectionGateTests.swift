import TalosAdapters
import TalosCore
import TalosProjectLibrary
import TalosSafeguards
import Testing

/// "No parsed third-party content can raise a tier" / "grant an allowlist
/// entry" / "trigger an irreversible action without the normal in-the-moment
/// approval" — asserted with hostile fixtures against the real
/// ``TieredSafeguardsGate``, not inferred from reading the source.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#prompt-injection-posture
private actor FixedAllowlist: SafeguardsAllowlist {
    private let answer: Bool
    init(_ answer: Bool) {
        self.answer = answer
    }

    func isAllowlisted(_: SafeguardsActionType, project _: ProjectIdentifier) async -> Bool {
        answer
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

private let testProject = ProjectIdentifier(rawValue: "p-1")

@Suite("Prompt-injection posture: the gate ignores hostile content in a permission request's prompt")
struct PromptInjectionGateRequestPromptTests {
    /// The hostile text sits in `request.prompt` — the CLI's own wording,
    /// shown to the user but never parsed by the gate — alongside a real
    /// `toolName`. If the gate read `prompt` for a directive, one of these
    /// fixtures would flip the outcome; none does, because `resolvedAction`
    /// only ever reads `toolName` and `connectorAccess`.
    @Test("A hostile prompt does not change a write-tier action's classification or allowlist consultation")
    func hostilePromptDoesNotChangeWriteTierClassification() async {
        for fixture in PromptInjectionFixtures.all {
            let allowlist = FixedAllowlist(false)
            let prompt = RecordingPrompt(.denied)
            let gate = TieredSafeguardsGate(allowlist: allowlist, approvalPrompt: prompt)
            let request = AgentPermissionRequest(id: "r1", prompt: fixture, toolName: "file.write")

            let decision = await gate.decide(request, project: testProject, subFunction: .automator)

            #expect(decision.classification == .tier(.write))
            #expect(decision.action == .fileWrite)
        }
    }

    @Test("A hostile prompt does not skip approval or unlock the allowlist for an irreversible action")
    func hostilePromptDoesNotSkipApprovalOnIrreversible() async {
        for fixture in PromptInjectionFixtures.all {
            let allowlist = FixedAllowlist(true)
            let prompt = RecordingPrompt(.denied)
            let gate = TieredSafeguardsGate(allowlist: allowlist, approvalPrompt: prompt)
            let request = AgentPermissionRequest(id: "r1", prompt: fixture, toolName: "deploy.production")

            let decision = await gate.decide(request, project: testProject, subFunction: .automator)

            #expect(decision.classification == .tier(.irreversible))
            #expect(decision.outcome == .denied)
            #expect(await prompt.presentedCount == 1)
        }
    }

    @Test("A hostile prompt does not reach a refused type's denial reasoning or open a prompt for it")
    func hostilePromptDoesNotAffectARefusedType() async {
        for fixture in PromptInjectionFixtures.all {
            let prompt = RecordingPrompt(.allowed)
            let gate = TieredSafeguardsGate(allowlist: FixedAllowlist(true), approvalPrompt: prompt)
            let request = AgentPermissionRequest(id: "r1", prompt: fixture, toolName: "config.allowlist.write")

            let decision = await gate.decide(request, project: testProject, subFunction: .automator)

            #expect(decision.classification == .refused)
            #expect(decision.outcome == .denied)
            #expect(await prompt.presentedCount == 0)
        }
    }
}

@Suite("Prompt-injection posture: hostile content used directly as a tool name defaults safely")
struct PromptInjectionGateToolNameTests {
    /// If an adapter ever forwarded parsed free text as `toolName` — which it
    /// must not, but this fixture proves what happens if it did — none of it
    /// is a `taxonomy: 1` name, so the classifier's unrecognized-call default
    /// applies: gated at the irreversible tier, never read, never
    /// allowlisted.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#action-classification
    @Test("Hostile content as a tool name is gated at the irreversible tier, not read")
    func hostileToolNameDefaultsToIrreversible() async {
        for fixture in PromptInjectionFixtures.all {
            let allowlist = FixedAllowlist(true)
            let prompt = RecordingPrompt(.denied)
            let gate = TieredSafeguardsGate(allowlist: allowlist, approvalPrompt: prompt)
            let request = AgentPermissionRequest(id: "r1", prompt: "do the thing", toolName: fixture)

            let decision = await gate.decide(request, project: testProject, subFunction: .automator)

            #expect(decision.classification == .tier(.irreversible))
            #expect(await prompt.presentedCount == 1)
        }
    }
}
