import Foundation
@testable import TalosAdapters
import Testing

/// Verifies ``AgentAdapter/stop()`` against § Stop kills the tree and § Rules.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
///
/// > **A surviving child is a failed stop, not a partial one.**
///
/// **What this suite does not claim.** It asserts the *contract* `stop()`
/// offers — no shape for a partial outcome, the run over, the stream closed,
/// callable while an approval waits. It does **not** assert that a real process
/// and its descendants are dead, because nothing here spawns one; the SPEC
/// states that assertion as "nothing survives", and it belongs to the first
/// adapter that spawns. Stated because a green run is otherwise read as a claim
/// it never made.
@Suite("Stop")
struct StopTests {
    // MARK: - Stop is a guarantee, not a request (AC5)

    /// The run is over when `stop()` returns, and the reason recorded is the
    /// user's own act rather than a failure.
    @Test("Stopping ends the run with the stopped reason")
    func stoppingEndsTheRunWithTheStoppedReason() async throws {
        let adapter = FakeAdapter()
        let stream = try await adapter.launch(TestLaunch.configuration())

        await adapter.stop()

        let events = try await AgentAdapterProtocolTests.collect(stream)
        guard case let .terminated(termination) = try #require(events.last) else {
            Issue.record("Expected a termination, got \(String(describing: events.last))")
            return
        }
        #expect(termination.reason == .stopped)
    }

    /// > An orphan keeps writing files, spending money, and holding locks after
    /// > the user has been told the session is over.
    ///
    /// Nothing arrives after a stop. An event emitted afterwards is not
    /// delivered, so a stopped session cannot keep reporting activity.
    @Test("Nothing is delivered after a stop")
    func nothingIsDeliveredAfterAStop() async throws {
        let adapter = FakeAdapter()
        let stream = try await adapter.launch(TestLaunch.configuration())

        await adapter.emit(.output(AgentOutputChunk(channel: .standardOutput, text: "before")))
        await adapter.stop()
        await adapter.emit(.output(AgentOutputChunk(channel: .standardOutput, text: "after")))

        let events = try await AgentAdapterProtocolTests.collect(stream)
        let texts = events.compactMap { event -> String? in
            guard case let .output(chunk) = event else { return nil }
            return chunk.text
        }
        #expect(texts == ["before"])
    }

    /// The stopped run carries the agent's own last output, so a stopped
    /// session is still recorded rather than vanishing.
    /// § The shared session model —
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
    @Test("A stopped run still carries what the agent last produced")
    func aStoppedRunStillCarriesTheLastOutput() async throws {
        let adapter = FakeAdapter()
        let stream = try await adapter.launch(TestLaunch.configuration())

        await adapter.emit(.output(AgentOutputChunk(channel: .standardOutput, text: "half an answer")))
        await adapter.stop()

        let events = try await AgentAdapterProtocolTests.collect(stream)
        guard case let .terminated(termination) = try #require(events.last) else {
            Issue.record("Expected a termination")
            return
        }
        #expect(termination.lastOutput == "half an answer")
    }

    /// > that prompt waits indefinitely with no timer
    ///
    /// So it is the state a session sits in longest, and the one where the user
    /// most wants out. Stop works with a permission request still unresolved.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed
    @Test("Stop works while a permission request is still waiting for a decision")
    func stopWorksWhileAPermissionRequestIsPending() async throws {
        let adapter = FakeAdapter()
        let stream = try await adapter.launch(TestLaunch.configuration())

        await adapter.emit(.permissionRequest(AgentPermissionRequest(id: "req-1", prompt: "Allow write_file?")))
        #expect(await adapter.openRequests == ["req-1"])

        await adapter.stop()

        #expect(await adapter.isTerminated)
        let events = try await AgentAdapterProtocolTests.collect(stream)
        guard case let .terminated(termination) = try #require(events.last) else {
            Issue.record("Expected a termination")
            return
        }
        #expect(termination.reason == .stopped)
    }

    /// A second stop is not a second termination: the run ended once, and the
    /// recorded reason is the one that ended it.
    @Test("Stopping twice does not end the run twice")
    func stoppingTwiceDoesNotEndTheRunTwice() async throws {
        let adapter = FakeAdapter()
        let stream = try await adapter.launch(TestLaunch.configuration())

        await adapter.stop()
        await adapter.stop()

        let events = try await AgentAdapterProtocolTests.collect(stream)
        let terminations = events.compactMap { event -> AgentTermination? in
            guard case let .terminated(termination) = event else { return nil }
            return termination
        }
        #expect(terminations.count == 1)
    }
}
