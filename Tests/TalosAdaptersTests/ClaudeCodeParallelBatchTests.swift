import Foundation
@testable import TalosAdapters
import Testing

/// A parallel tool-call batch defers every call, but the `result` line names
/// only one `deferred_tool_use` and reports `permission_denials: []`. The rest
/// are dropped with no mention anywhere in the stream. The adapter recovers
/// them from the calls it saw announced, so a gate the CLI could never offer a
/// decision to still fails closed rather than letting the call vanish silently.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed
@Suite("Parallel tool-call batch")
struct ClaudeCodeParallelBatchTests {
    @Test("A batched call the result never names surfaces as permissionUnavailable")
    func droppedBatchCallFailsClosed() async throws {
        let executablePath = try ClaudeCodeFakeExecutable.write()
        let configuration = ClaudeCodeFakeExecutable.configuration(
            launchResponse: ClaudeCodeFixture.path("parallel-batch-drop.jsonl"),
            resumeResponse: ClaudeCodeFixture.path("token-report.jsonl")
        )
        let adapter = ClaudeCodeAdapter(executableOverride: executablePath)
        let stream = try await adapter.launch(configuration)

        try await adapter.send(AgentPrompt(text: "Read both files."))
        var iterator = stream.makeAsyncIterator()

        // Both calls are announced, then the result defers only the second: the
        // gate is offered the second and the first arrives as a fail-closed
        // denial with no decision to obtain.
        guard case let .toolCall(first) = try await iterator.next(),
              case .toolCall = try await iterator.next(),
              case let .permissionRequest(request) = try await iterator.next(),
              case let .permissionUnavailable(unavailable) = try await iterator.next()
        else {
            Issue.record("Expected two tool calls, a permission request, then a permissionUnavailable")
            return
        }
        #expect(request.id == "toolu_fixture_bash_b", "the result names the second call")
        #expect(unavailable.id == first.id, "the dropped first call is the one made unavailable")
        #expect(unavailable.toolName == "Bash")

        await adapter.stop()
    }

    @Test("Resuming after the drop tells the agent what was not run")
    func resumeCarriesTheUndeliverableNotice() async throws {
        let executablePath = try ClaudeCodeFakeExecutable.write()
        let capturePath = NSTemporaryDirectory() + "talos-prompt-capture-\(UUID().uuidString)"
        let configuration = ClaudeCodeFakeExecutable.configuration(
            launchResponse: ClaudeCodeFixture.path("parallel-batch-drop.jsonl"),
            resumeResponse: ClaudeCodeFixture.path("token-report.jsonl"),
            promptCapturePath: capturePath
        )
        let adapter = ClaudeCodeAdapter(executableOverride: executablePath)
        let stream = try await adapter.launch(configuration)

        try await adapter.send(AgentPrompt(text: "Read both files."))
        var iterator = stream.makeAsyncIterator()
        var deferredID: String?
        while let event = try await iterator.next() {
            if case let .permissionRequest(request) = event {
                deferredID = request.id
                break
            }
        }
        let id = try #require(deferredID)

        try await adapter.resolve(id, with: .allowed)

        // Drain to the resume turn's own termination, so the fake has actually
        // run and appended that turn's argv before the capture is read.
        while let event = try await iterator.next() {
            if case .terminated = event {
                break
            }
        }

        let captured = try String(contentsOfFile: capturePath, encoding: .utf8)
        #expect(captured.contains("Not run"), "the resume prompt tells the agent the dropped call was not run")
        #expect(captured.contains("cat one.txt"), "and names it, so the agent re-issues it singly")
    }
}
