import TalosAdapters
import TalosOrchestration
import TalosSafeguards
import Testing

/// `onDenial` fires for a blocked retry the same as for a fresh denial, since
/// neither one asked the gate a second time — the retry has no prompt of its
/// own to be counted by, so this checks the callback directly rather than
/// through `SafeguardsApprovalPrompt.presentCount`.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#denial-is-not-failure
@Suite("onDenial fires for a blocked retry")
struct DeniedActionOnDenialTests {
    @Test("onDenial fires for both the fresh denial and the blocked retry")
    func onDenialFiresForTheBlockedRetry() async {
        let deniedCall = AgentToolCall(id: "t1", name: "Bash", targets: ["rm -rf /tmp/scratch"])
        let retryCall = AgentToolCall(id: "t2", name: "Bash", targets: ["rm -rf /tmp/scratch"])
        let adapter = ScriptedAgentAdapter(events: [
            .toolCall(deniedCall),
            .permissionRequest(AgentPermissionRequest(id: "t1", prompt: "Delete /tmp/scratch", toolName: "Bash")),
            .toolCall(retryCall),
            .permissionRequest(AgentPermissionRequest(id: "t2", prompt: "Delete /tmp/scratch", toolName: "Bash")),
            terminated(.exited(code: 0))
        ])
        let gate = RecordingSafeguardsGate(.denied)
        let pipeline = makeTestPipeline(adapter: adapter, gate: gate)
        let notifiedPrompts = DeniedPromptRecorder()

        _ = await runTestSession(pipeline, onDenial: { await notifiedPrompts.record($1) })

        #expect(await notifiedPrompts.prompts == ["Delete /tmp/scratch", "Delete /tmp/scratch"])
    }
}

/// Independently observes every call `onDenial` actually received, so a
/// regression that stops calling it for the blocked path is caught here
/// rather than only through the approval prompt's own count.
private actor DeniedPromptRecorder {
    private(set) var prompts: [String] = []

    func record(_ prompt: String) {
        prompts.append(prompt)
    }
}
