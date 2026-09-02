import TalosAdapters
import TalosOrchestration
import Testing

/// The default test guideline requests `memories`, a droppable part — which
/// "is data, never instruction". It must reach the agent framed as data, not
/// as bare text indistinguishable from the guideline. Kept apart from
/// `SessionPipelineTests` so that suite's own line-length budget is
/// untouched by this issue's addition.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#prompt-injection-posture
@Suite("Session pipeline: droppable context reaches the agent framed as data")
struct PromptDataFramingPipelineTests {
    @Test("A droppable context part reaches the agent framed as data")
    func droppablePartReachesTheAgentFramedAsData() async {
        let adapter = ScriptedAgentAdapter(events: [terminated(.exited(code: 0))])
        let pipeline = makeTestPipeline(adapter: adapter)

        _ = await runTestSession(pipeline)

        let text = await adapter.sentPrompts.first?.text
        #expect(text?.contains("<data source=\"memories\">\nPrefers dark mode.\n</data>") == true)
    }
}
