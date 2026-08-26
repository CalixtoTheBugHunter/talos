import Foundation
@testable import TalosAdapters
import Testing

/// Asserts that leaving a permission request unresolved is a legitimate,
/// indefinite state rather than one that times out or drops.
/// > A pending prompt has no timer.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy
@Suite("Pending permission request")
struct ClaudeCodePendingRequestTests {
    @Test("An unresolved request does not end the session or block other calls")
    func unresolvedRequestHasNoDeadline() async throws {
        let executablePath = try ClaudeCodeFakeExecutable.write()
        let configuration = ClaudeCodeFakeExecutable.configuration(
            launchResponse: ClaudeCodeFixture.path("both-together.jsonl"),
            resumeResponse: ClaudeCodeFixture.path("token-report.jsonl")
        )
        let adapter = ClaudeCodeAdapter(executableOverride: executablePath)
        let stream = try await adapter.launch(configuration)

        try await adapter.send(AgentPrompt(text: "Write a file."))

        // No resolve() call at all — the request just waits, with nothing here
        // on a clock that would deny or drop it for staying unanswered.
        let usage = await adapter.tokenUsage()
        #expect(usage == .measured(TokenCounts(input: 2, output: 89), model: "global.anthropic.claude-opus-5"))

        await adapter.stop()

        var events: [AgentEvent] = []
        for try await event in stream {
            events.append(event)
        }

        guard case .toolCall = events[0], case .permissionRequest = events[1], case .terminated = events[2] else {
            Issue.record("Expected [toolCall, permissionRequest, terminated], got \(events)")
            return
        }
    }
}
