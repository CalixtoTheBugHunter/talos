import Foundation
@testable import TalosAdapters
import Testing

/// Asserts that a launch configuration carrying a prior run's resume token
/// continues that agent session from its very first turn — "resuming uses
/// the agent's own resume mechanism where available" — and that this run's
/// own resume token is in turn carried forward on ``AgentTermination``, ready
/// for a later resume.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
@Suite("Resume")
struct ClaudeCodeResumeTests {
    @Test("A launch configuration carrying a resume token resumes on the very first turn, not a fresh launch")
    func launchWithResumeTokenResumesFirstTurn() async throws {
        let executablePath = try ClaudeCodeFakeExecutable.write()
        let configuration = ClaudeCodeFakeExecutable.configuration(
            launchResponse: ClaudeCodeFixture.path("tool-call.jsonl"),
            resumeResponse: ClaudeCodeFixture.path("token-report.jsonl"),
            resumeToken: "prior-session-id"
        )
        let adapter = ClaudeCodeAdapter(executableOverride: executablePath)
        let stream = try await adapter.launch(configuration)

        try await adapter.send(AgentPrompt(text: "Continue."))

        // A turn that exits 0 does not finish the outer stream on its own —
        // an ordinary turn and a deferred permission request both end that
        // way, and either could be followed by another `send`/`resolve`.
        // `stop()` is what actually ends this session.
        await adapter.stop()

        var events: [AgentEvent] = []
        for try await event in stream {
            events.append(event)
        }

        // `tool-call.jsonl` would have produced a `.toolCall` event first;
        // seeing none proves the *resume* fixture — `token-report.jsonl` —
        // was read on the very first turn, never the launch one.
        #expect(!events.contains {
            if case .toolCall = $0 {
                true
            } else {
                false
            }
        })
        guard case let .terminated(termination) = events.last else {
            Issue.record("Expected the run to end with a termination event")
            return
        }
        // `token-report.jsonl`'s own reported session id — proved reachable
        // only by resuming, and carried forward for a later resume.
        #expect(termination.resumeToken == "fixture-session-token-report")
    }
}
