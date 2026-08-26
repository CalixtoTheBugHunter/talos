import Foundation
@testable import TalosAdapters
import Testing

/// Verifies that ``AgentAdapter`` declares the six capabilities § Agent adapters
/// specifies — one test per capability, each stating the SPEC line it holds to.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#agent-adapters
///
/// > Each supported agent is a **thin adapter** declaring:
/// > how to launch it · how to pass a prompt · how to stream its output · how to
/// > detect a tool call or a permission request · how to report token usage ·
/// > how to stop it
@Suite("Agent adapter protocol")
struct AgentAdapterProtocolTests {
    // MARK: - Capability 1 — how to launch it (AC1)

    /// > how to launch it
    ///
    /// The working directory and environment are explicit, and they cross to
    /// the adapter exactly as given — nothing is inherited that core did not
    /// name.
    @Test("Launching hands the adapter an explicit working directory and environment")
    func launchCarriesAnExplicitWorkingDirectoryAndEnvironment() async throws {
        let adapter = FakeAdapter()
        let configuration = TestLaunch.configuration()

        _ = try await adapter.launch(configuration)

        #expect(await adapter.launchConfiguration == configuration)
    }

    // MARK: - Capability 2 — how to pass a prompt (AC1)

    /// > how to pass a prompt
    ///
    /// Talos assembles the prompt and the adapter transports it. It does not
    /// edit, summarize, re-order, or append to it, so what arrives is what was
    /// sent.
    @Test("A prompt is transported verbatim")
    func promptIsTransportedVerbatim() async throws {
        let adapter = FakeAdapter()
        _ = try await adapter.launch(TestLaunch.configuration())
        let prompt = AgentPrompt(text: "Read safeguards.md, then summarize the tiers.\n\nDo not edit anything.")

        try await adapter.send(prompt)

        #expect(await adapter.sentPrompts == [prompt])
    }

    /// Sending before a launch is an error rather than a silent no-op: a prompt
    /// that went nowhere must not look like one that was delivered.
    @Test("Sending a prompt before launching fails rather than silently dropping it")
    func sendingBeforeLaunchFails() async {
        let adapter = FakeAdapter()

        await #expect(throws: AgentNotRunningError.self) {
            try await adapter.send(AgentPrompt(text: "anything"))
        }
    }

    // MARK: - Capability 3 — how to stream its output (AC1, AC2)

    /// > how to stream its output
    ///
    /// An async sequence, consumed incrementally. The first chunk is readable
    /// before the second one exists, which is what an adapter that buffered to
    /// completion could not do — and the console is specified to show output
    /// "as it happens".
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
    @Test("Output is readable chunk by chunk, before the run has finished")
    func outputIsReadableBeforeTheRunFinishes() async throws {
        let adapter = FakeAdapter()
        let stream = try await adapter.launch(TestLaunch.configuration())
        var events = stream.makeAsyncIterator()

        await adapter.emit(.output(AgentOutputChunk(channel: .standardOutput, text: "first")))
        let first = try await events.next()
        #expect(first == .output(AgentOutputChunk(channel: .standardOutput, text: "first")))

        await adapter.emit(.output(AgentOutputChunk(channel: .standardOutput, text: "second")))
        let second = try await events.next()
        #expect(second == .output(AgentOutputChunk(channel: .standardOutput, text: "second")))

        #expect(await adapter.isTerminated == false)
    }

    /// The stream distinguishes the agent's own diagnostics from its answer, so
    /// a console reading it can attribute each.
    @Test("Standard output and standard error stay distinguishable")
    func standardOutputAndStandardErrorStayDistinguishable() async throws {
        let adapter = FakeAdapter()
        let stream = try await adapter.launch(TestLaunch.configuration())

        await adapter.emit(.output(AgentOutputChunk(channel: .standardOutput, text: "answer")))
        await adapter.emit(.output(AgentOutputChunk(channel: .standardError, text: "warning")))
        await adapter.emit(.terminated(AgentTermination(reason: .exited(code: 0), lastOutput: "warning")))

        let channels = try await Self.collect(stream).compactMap { event -> AgentOutputChannel? in
            guard case let .output(chunk) = event else { return nil }
            return chunk.channel
        }
        #expect(channels == [.standardOutput, .standardError])
    }

    // MARK: - Capability 4 — detecting a tool call or a permission request (AC1)

    /// > how to detect a tool call or a permission request
    ///
    /// The detection half is the two distinct event types — asserted in
    /// ``AgentEventTests``. This is the return half: the adapter "surfaces the
    /// request and carries back the decision the gate produced", which
    /// discharges the same capability rather than adding a seventh.
    /// § A tool call and a permission request are two events —
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
    @Test("The decision carried back to a permission request is the one it was given")
    func theCarriedDecisionIsTheOneItWasGiven() async throws {
        let adapter = FakeAdapter()
        _ = try await adapter.launch(TestLaunch.configuration())
        await adapter.emit(.permissionRequest(AgentPermissionRequest(id: "req-1", prompt: "Allow writing to disk?")))

        try await adapter.resolve("req-1", with: .denied)

        #expect(await adapter.carriedDecisions["req-1"] == .denied)
        #expect(await adapter.openRequests.isEmpty)
    }

    /// An adapter has no answer of its own to give: resolving a request nobody
    /// raised fails rather than inventing consent, because a record naming a
    /// user who never decided is the defect this guards.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
    @Test("Resolving a request that was never raised fails")
    func resolvingAnUnraisedRequestFails() async throws {
        let adapter = FakeAdapter()
        _ = try await adapter.launch(TestLaunch.configuration())

        await #expect(throws: AgentNotRunningError.self) {
            try await adapter.resolve("never-raised", with: .allowed)
        }
    }

    // MARK: - Capability 5 — how to report token usage (AC1, AC4)

    /// > how to report token usage
    ///
    /// A value, not text. Asserted in detail by ``TokenReportTests``; here
    /// only that the capability exists on the protocol and yields a
    /// ``TokenReport``.
    @Test("Token usage is reported as a value, at the protocol level")
    func tokenUsageIsReportedAsAValue() async throws {
        let adapter = FakeAdapter(usage: .measured(TokenCounts(input: 7, output: 3), model: "test-model"))
        _ = try await adapter.launch(TestLaunch.configuration())

        #expect(await adapter.tokenUsage() == .measured(TokenCounts(input: 7, output: 3), model: "test-model"))
    }

    // MARK: - Capability 6 — how to stop it (AC1, AC5)

    /// > how to stop it
    ///
    /// Asserted in detail by ``StopTests``; here only that the capability
    /// exists and ends the run.
    @Test("Stopping ends the run")
    func stoppingEndsTheRun() async throws {
        let adapter = FakeAdapter()
        _ = try await adapter.launch(TestLaunch.configuration())

        await adapter.stop()

        #expect(await adapter.isTerminated)
    }

    // MARK: - Helpers

    /// Drains `stream` to its end. Safe because every fake run in these suites
    /// terminates.
    static func collect(_ stream: AgentEventStream) async throws -> [AgentEvent] {
        var events: [AgentEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }
}
