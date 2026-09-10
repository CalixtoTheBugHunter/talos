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

        // `send` transports the prompt and returns; the turn's events arrive on
        // the stream. Reading to the pending request proves the turn ran and
        // its result line was drained.
        try await adapter.send(AgentPrompt(text: "Write a file."))
        var iterator = stream.makeAsyncIterator()
        guard case .toolCall = try await iterator.next() else {
            Issue.record("Expected a tool call first")
            return
        }
        guard case .permissionRequest = try await iterator.next() else {
            Issue.record("Expected a permission request second")
            return
        }

        // The request is left unresolved: the session neither ends nor blocks a
        // further call, and the turn's usage is readable.
        let usage = await adapter.tokenUsage()
        #expect(usage == .measured(TokenCounts(input: 2, output: 89), model: "global.anthropic.claude-opus-5"))

        // Only a stop ends it — "a pending prompt has no timer."
        await adapter.stop()
        guard case .terminated = try await iterator.next() else {
            Issue.record("Expected a terminated event once stopped")
            return
        }
    }
}
