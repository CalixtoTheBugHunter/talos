import Foundation
@testable import TalosAdapters
import Testing

/// Verifies the event types against § A tool call and a permission request are
/// two events, and § Errors.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#errors
///
/// > **An adapter reports a tool call and a permission request as distinct,
/// > separately typed events — never as one.**
@Suite("Agent events")
struct AgentEventTests {
    // MARK: - Two events, not one (AC3)

    /// A tool call is the agent stating what it intends to do — what the gate
    /// intercepts.
    @Test("A tool call arrives as a tool call, naming the tool and its targets")
    func aToolCallArrivesAsAToolCall() async throws {
        let events = try await Self.run { adapter in
            await adapter.emit(.toolCall(AgentToolCall(id: "call-1", name: "write_file", targets: ["README.md"])))
        }

        guard case let .toolCall(call) = try #require(events.first) else {
            Issue.record("Expected a tool call, got \(String(describing: events.first))")
            return
        }
        #expect(call.name == "write_file")
        #expect(call.targets == ["README.md"])
    }

    /// > The operation and the target are named, with counts and paths rather
    /// > than a category.
    ///
    /// So a call against four files reaches the gate as four paths. The
    /// regression this asserts: collapsing them into one string would leave the
    /// approval prompt to either name a category or parse the string back
    /// apart, and the count is what a user reads first.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice
    @Test("A call against several files carries every path, not a joined string")
    func aCallAgainstSeveralFilesCarriesEveryPath() async throws {
        let paths = [
            "Sources/Talos/Legacy/Old.swift",
            "Sources/Talos/Legacy/Older.swift",
            "Sources/Talos/Legacy/Oldest.swift",
            "Sources/Talos/Legacy/Ancient.swift"
        ]
        let events = try await Self.run { adapter in
            await adapter.emit(.toolCall(AgentToolCall(id: "call-1", name: "delete_files", targets: paths)))
        }

        guard case let .toolCall(call) = try #require(events.first) else {
            Issue.record("Expected a tool call, got \(String(describing: events.first))")
            return
        }
        #expect(call.targets == paths)
        #expect(call.targets.count == 4)
    }

    /// An agent that stated no target produces no target, which the gate
    /// classifies as unstated rather than as none.
    @Test("A call with no stated target carries no targets")
    func aCallWithNoStatedTargetCarriesNone() {
        let call = AgentToolCall(id: "call-1", name: "list_tools")

        #expect(call.targets.isEmpty)
    }

    /// A permission request is the agent's CLI asking for consent of its own
    /// accord — a question put to Talos rather than an intent to run.
    @Test("A permission request arrives as a permission request, carrying the CLI's own wording")
    func aPermissionRequestArrivesAsAPermissionRequest() async throws {
        let events = try await Self.run { adapter in
            await adapter.emit(.permissionRequest(
                AgentPermissionRequest(id: "req-1", prompt: "Allow write_file?", toolName: "write_file")
            ))
        }

        guard case let .permissionRequest(request) = try #require(events.first) else {
            Issue.record("Expected a permission request, got \(String(describing: events.first))")
            return
        }
        #expect(request.prompt == "Allow write_file?")
        #expect(request.toolName == "write_file")
    }

    /// The regression this suite exists for. Both arrive on the same stream in
    /// a similar shape, so a run containing one of each must produce one of
    /// each case — never two of the same, and never one event with a flag.
    ///
    /// > Collapsing them removes the gate.
    @Test("A run containing both a tool call and a permission request does not collapse them")
    func aRunContainingBothDoesNotCollapseThem() async throws {
        let events = try await Self.run { adapter in
            await adapter.emit(.toolCall(AgentToolCall(id: "call-1", name: "write_file", targets: ["README.md"])))
            await adapter.emit(.permissionRequest(
                AgentPermissionRequest(id: "req-1", prompt: "Allow write_file?", toolName: "write_file")
            ))
        }

        let toolCalls = events.compactMap { event -> AgentToolCall? in
            guard case let .toolCall(call) = event else { return nil }
            return call
        }
        let permissionRequests = events.compactMap { event -> AgentPermissionRequest? in
            guard case let .permissionRequest(request) = event else { return nil }
            return request
        }
        #expect(toolCalls.count == 1)
        #expect(permissionRequests.count == 1)
    }

    /// The two cases are not interchangeable even when they describe the same
    /// tool, which is what makes the distinction structural rather than a
    /// matter of which string the adapter matched.
    @Test("A tool call and a permission request for the same tool are not equal")
    func aToolCallAndAPermissionRequestForTheSameToolAreNotEqual() {
        let call = AgentEvent.toolCall(AgentToolCall(id: "x", name: "write_file", targets: ["README.md"]))
        let request = AgentEvent.permissionRequest(
            AgentPermissionRequest(id: "x", prompt: "Allow write_file?", toolName: "write_file")
        )

        #expect(call != request)
    }

    // MARK: - Termination is typed and attributed (AC3)

    /// > Talos **attributes it to the agent** and shows the agent's own output
    /// > instead of paraphrasing it.
    @Test("An abnormal exit carries the exit code and the agent's own last output")
    func anAbnormalExitCarriesTheCodeAndTheAgentsOwnOutput() async throws {
        let events = try await Self.run(
            terminatedBy: .init(reason: .exited(code: 2), lastOutput: "fatal: no such file")
        ) { adapter in
            await adapter.emit(.output(AgentOutputChunk(channel: .standardError, text: "fatal: no such file")))
        }

        guard case let .terminated(termination) = try #require(events.last) else {
            Issue.record("Expected a termination, got \(String(describing: events.last))")
            return
        }
        #expect(termination.reason == .exited(code: 2))
        #expect(termination.lastOutput == "fatal: no such file")
    }

    /// > **Recorded as denied**, not as an error, everywhere outcomes appear.
    ///
    /// A denial and a crash are different reasons, so a denial can never render
    /// as a failure.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#denial-is-not-failure
    @Test("A denial is a different termination reason from an abnormal exit")
    func aDenialIsNotAnAbnormalExit() {
        #expect(AgentTerminationReason.denied != .exited(code: 1))
        #expect(AgentTerminationReason.denied != .failedToLaunch)
        #expect(AgentTerminationReason.stopped != .denied)
    }

    /// The stream ends after the termination event, so a consumer never has to
    /// guess whether more is coming.
    @Test("The termination event is the last one on the stream")
    func terminationIsTheLastEvent() async throws {
        let events = try await Self.run { adapter in
            await adapter.emit(.output(AgentOutputChunk(channel: .standardOutput, text: "done")))
        }

        #expect(events.count == 2)
        guard case .terminated = try #require(events.last) else {
            Issue.record("Expected the last event to be a termination")
            return
        }
    }

    // MARK: - Helpers

    /// Launches a fake adapter, lets `body` emit events, terminates the run,
    /// and returns everything the stream yielded.
    static func run(
        terminatedBy termination: AgentTermination = .init(reason: .exited(code: 0)),
        _ body: (FakeAdapter) async -> Void
    ) async throws -> [AgentEvent] {
        let adapter = FakeAdapter()
        let stream = try await adapter.launch(TestLaunch.configuration())
        await body(adapter)
        await adapter.emit(.terminated(termination))
        return try await AgentAdapterProtocolTests.collect(stream)
    }
}
