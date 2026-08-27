import Foundation
@testable import TalosAdapters
import Testing

/// Verifies the SPEC's claim:
/// "**Adding an agent means writing one adapter, never touching Talos core.**"
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#agent-adapters
///
/// One suite, two different kinds of proof: a full session driven through
/// ``StubAdapter`` in the order the SPEC states the capabilities (AC2), and a
/// static read of the stub's own source asserting it needed nothing beyond
/// `Foundation` to do it (AC3).
@Suite("The stub adapter proves the abstraction")
struct StubAdapterTests {
    // MARK: - AC2: launch → prompt → stream → tool call → token report → stop

    /// A single continuous run through every capability the SPEC names, in the
    /// order it names them — distinct from ``AgentAdapterProtocolTests``, which
    /// verifies each capability in isolation.
    @Test("A full session runs launch, prompt, stream, tool call, token report, and stop in order")
    func aFullSessionRunsEveryCapabilityInOrder() async throws {
        let adapter = StubAdapter(usage: .measured(TokenCounts(input: 42, output: 17), model: "stub-model"))

        // launch
        let stream = try await adapter.launch(TestLaunch.configuration())
        var iterator = stream.makeAsyncIterator()

        // prompt
        try await adapter.send(AgentPrompt(text: "List the files in this project."))

        // stream
        await adapter.emit(.output(AgentOutputChunk(channel: .standardOutput, text: "Listing files...")))
        let streamed = try await iterator.next()
        #expect(streamed == .output(AgentOutputChunk(channel: .standardOutput, text: "Listing files...")))

        // tool call
        await adapter.emit(.toolCall(AgentToolCall(id: "call-1", name: "list_files", targets: ["."])))
        let toolCallEvent = try await iterator.next()
        guard case let .toolCall(call) = try #require(toolCallEvent) else {
            Issue.record("Expected a tool call, got \(String(describing: toolCallEvent))")
            return
        }
        #expect(call.name == "list_files")

        // token report
        let usage = await adapter.tokenUsage()
        #expect(usage == .measured(TokenCounts(input: 42, output: 17), model: "stub-model"))

        // stop
        await adapter.stop()
        let terminatedEvent = try await iterator.next()
        guard case let .terminated(termination) = try #require(terminatedEvent) else {
            Issue.record("Expected a termination, got \(String(describing: terminatedEvent))")
            return
        }
        #expect(termination.reason == .stopped)
    }

    // MARK: - AC3: zero files outside the adapter module were needed

    /// The checkable form of "no Talos core changes": the stub's own source
    /// imports nothing but `Foundation` — no `TalosCore`, no sibling target, no
    /// upward dependency on anything the second adapter would also have to
    /// pull in. If proving the six capabilities needed a Talos module beyond
    /// this one, this is the file that would show it.
    @Test("The stub's own source imports nothing but Foundation")
    func theStubImportsNothingButFoundation() throws {
        let url = NoAgentOrProviderReferenceTests.moduleURL
            .appendingPathComponent("Stub")
            .appendingPathComponent("StubAdapter.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        let importLines = source
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("import ") }

        #expect(importLines == ["import Foundation"])
    }
}
