import Foundation
import TalosAdapters
import TalosOrchestration
import TalosProjectLibrary
import TalosSafeguards
import Testing

/// Asserts that a session's transcript and its own resume token — what a
/// later resume reads back from `SQLiteSessionRecordStore` — reach
/// `SessionRecord` unchanged from what the adapter's stream actually
/// produced.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
@Suite("Session record transcript")
struct SessionRecordTranscriptTests {
    @Test("Output and tool-call events reach the record's transcript, in arrival order")
    func transcriptMatchesStreamOrder() async {
        let call = AgentToolCall(id: "t1", name: "Read", targets: ["README.md"])
        let adapter = ScriptedAgentAdapter(events: [
            .output(AgentOutputChunk(channel: .standardOutput, text: "Reading the file.\n")),
            .toolCall(call),
            .output(AgentOutputChunk(channel: .standardOutput, text: "Done.\n")),
            terminated(.exited(code: 0))
        ])
        let pipeline = makeTestPipeline(adapter: adapter)

        let record = await runTestSession(pipeline)

        #expect(record.transcript == [
            .output("Reading the file.\n"),
            .toolCall(id: "t1", name: "Read", targets: ["README.md"]),
            .output("Done.\n")
        ])
    }

    @Test("The agent's own resume token on termination reaches the record")
    func resumeTokenReachesTheRecord() async {
        let adapter = ScriptedAgentAdapter(events: [
            .terminated(AgentTermination(reason: .exited(code: 0), resumeToken: "claude-session-42"))
        ])
        let pipeline = makeTestPipeline(adapter: adapter)

        let record = await runTestSession(pipeline)

        #expect(record.resumeToken == "claude-session-42")
    }

    @Test("A session that never launches an agent has an empty transcript and no resume token")
    func neverLaunchedSessionHasNoTranscriptOrResumeToken() async {
        let pipeline = SessionPipeline(
            assembler: makeTestAssembler(),
            preCheck: FixedSafeguardsPreCheck(.approved),
            adapter: ScriptedAgentAdapter(),
            gate: RecordingSafeguardsGate(),
            decisionLog: RecordingGatedDecisionLog(),
            recordWriter: RecordingSessionRecordWriter(),
            memories: RecordingMemoriesUpdatePort()
        )

        let record = await pipeline.run(
            intent: makeTestIntent(),
            guideline: makeTestGuideline(context: ["memories"], tokenCeiling: 1),
            safeguards: makeTestSafeguards(),
            connectors: makeTestConnectors(),
            launch: SessionLaunch(agentName: testAgentName, configuration: TestLaunch.configuration())
        )

        #expect(record.transcript.isEmpty)
        #expect(record.resumeToken == nil)
    }
}
