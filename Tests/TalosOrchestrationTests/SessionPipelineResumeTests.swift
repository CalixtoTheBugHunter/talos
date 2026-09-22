import Foundation
import TalosAdapters
import TalosOrchestration
import TalosProjectLibrary
import Testing

/// A follow-up turn resumes the session with the prior run's own resume token,
/// and the agent already holds the prior conversation through that mechanism —
/// so Talos assembles no context and sends only the user's follow-up text. The
/// launch carrying a `resumeToken` is the signal the pipeline branches on.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
@Suite("Session pipeline: a resumed turn assembles no context")
struct SessionPipelineResumeTests {
    private func resumeLaunch() -> SessionLaunch {
        SessionLaunch(
            agentName: testAgentName,
            configuration: AgentLaunchConfiguration(
                workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
                environment: ["PATH": "/usr/bin:/bin"],
                resumeToken: "prior-session-id"
            )
        )
    }

    @Test("A resumed turn sends only the user's follow-up text — no guideline, no Safeguards copy")
    func resumedTurnSendsOnlyTheUserText() async {
        let adapter = ScriptedAgentAdapter(events: [terminated(.exited(code: 0))])
        let pipeline = makeTestPipeline(adapter: adapter)
        let intent = makeTestIntent(content: "Call the branch \"dark-mode\".")

        _ = await pipeline.run(
            intent: intent,
            guideline: makeSessionGuideline(),
            safeguards: makeTestSafeguards(),
            connectors: makeTestConnectors(),
            launch: resumeLaunch()
        )

        let text = await adapter.sentPrompts.first?.text
        #expect(text == intent.content)
        // The pinned parts the fresh path always injects are absent here: the
        // agent carries them from the turn it was first told them on.
        #expect(text?.contains("Answer questions grounded") == false)
        #expect(text?.contains("Never deploy on a Friday.") == false)
    }

    @Test("The context a resumed turn assembles adds zero Talos overhead")
    func resumedContextAddsNoOverhead() {
        let context = AssembledContext.none(rawPromptTokenEstimate: 42)
        #expect(context.includedParts.isEmpty)
        #expect(context.droppedParts.isEmpty)
        #expect(context.unavailableParts.isEmpty)
        #expect(context.overheadRatio == 0)
    }
}
