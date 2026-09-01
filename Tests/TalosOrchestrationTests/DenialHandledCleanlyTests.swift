import TalosAdapters
import TalosCore
import TalosOrchestration
import TalosProjectLibrary
import TalosSafeguards
import Testing

/// A real mutation, denied through the real gate, asserting every piece of
/// "a denial handled cleanly" together rather than one at a time.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#notes-on-the-harder-criteria
///
/// The user-visible half of "a denial handled cleanly" — a clear,
/// non-alarming indication — is `SessionRun`'s `onDenial` callback, asserted
/// below for both the interactive denial and the blocked retry alike: a
/// blocked repeat never reaches the approval prompt, so it needed its own
/// path to the user rather than inheriting the prompt's.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#denial-is-not-failure
@Suite("Denial handled cleanly")
struct DenialHandledCleanlyTests {
    @Test(
        "Denying a real mutation informs the agent, keeps the session alive, applies nothing, and blocks a silent retry"
    )
    func denyingARealMutationIsHandledCleanly() async {
        let mutation = AgentToolCall(id: "t1", name: "file.write", targets: ["Sources/App/Secrets.swift"])
        let retry = AgentToolCall(id: "t2", name: "file.write", targets: ["Sources/App/Secrets.swift"])
        let adapter = ScriptedAgentAdapter(events: [
            .toolCall(mutation),
            .permissionRequest(AgentPermissionRequest(id: "t1", prompt: "Write Secrets.swift", toolName: "file.write")),
            .toolCall(retry),
            .permissionRequest(AgentPermissionRequest(id: "t2", prompt: "Write Secrets.swift", toolName: "file.write")),
            terminated(.exited(code: 0))
        ])
        let prompt = DenyingApprovalPrompt()
        let gate = TieredSafeguardsGate(allowlist: NeverAllowlisted(), approvalPrompt: prompt)
        let log = RecordingGatedDecisionLog()
        let sideEffect = SideEffectSpy()
        let deniedNotices = RecordingDeniedNotices()
        let pipeline = makeTestPipeline(adapter: adapter, gate: gate, decisionLog: log)

        let record = await runTestSession(pipeline, onDenial: { await deniedNotices.record($0, $1) })

        // AC1 + AC2: the agent was told, through the normal carry-back path,
        // and the session finished as an ordinary successful run rather than
        // failing or crashing.
        #expect(record.outcome == .succeeded(TestDefaults.usage))
        #expect(await adapter.carriedDecisions == ["t1": .denied, "t2": .denied])

        // AC3: nothing about the mutation was applied. `SideEffectSpy` is
        // marked only by an `.allowed` outcome, mirroring how the agent CLI
        // itself would decide whether to perform the write.
        await sideEffect.apply(if: adapter.carriedDecisions["t1"])
        await sideEffect.apply(if: adapter.carriedDecisions["t2"])
        #expect(await sideEffect.applied == false)

        // AC4: the retry was blocked rather than merely counted — the prompt
        // was shown once, not twice, so the user was never asked about the
        // same write a second time.
        #expect(await prompt.presentCount == 1)
        #expect(record.retryCount == 1)

        // AC5: recorded in both the session record and the audit log.
        #expect(record.denialCount == 2)
        #expect(await log.entries.map(\.outcome) == [.denied, .denied])
        #expect(await log.entries.map(\.actor) == [.user, .talos])

        // AC6: the user was told, for both denials — including the blocked
        // retry, which never showed the prompt at all.
        #expect(await deniedNotices.actions == [.fileWrite, .fileWrite])
    }
}

/// Independently observes every call `onDenial` actually received, so a
/// regression that stops calling it for the blocked path is caught here
/// rather than only in the prompt's own count.
private actor RecordingDeniedNotices {
    private(set) var actions: [SafeguardsActionType] = []

    func record(_ action: SafeguardsActionType, _: String) {
        actions.append(action)
    }
}

/// Never allowlists anything — the write-tier action in this test always
/// reaches the prompt, the same as an unconfigured project.
private struct NeverAllowlisted: SafeguardsAllowlist {
    func isAllowlisted(_: SafeguardsActionType, project _: ProjectIdentifier) async -> Bool {
        false
    }
}

/// Denies every request it is shown and counts how many times it was asked —
/// the count is what proves a blocked retry never reached the prompt again.
private actor DenyingApprovalPrompt: SafeguardsApprovalPrompt {
    private(set) var presentCount = 0

    func present(
        _: AgentPermissionRequest,
        action _: SafeguardsActionType,
        tier _: SafeguardsTier
    ) async -> AgentPermissionDecision? {
        presentCount += 1
        return .denied
    }
}

/// Stands in for the mutation an agent CLI would perform after being told
/// `.allowed` — never called for a `.denied` outcome, so a test can assert
/// nothing was half-applied without Talos itself touching a filesystem or a
/// board.
private actor SideEffectSpy {
    private(set) var applied = false

    func apply(if decision: AgentPermissionDecision?) {
        if decision == .allowed {
            applied = true
        }
    }
}
