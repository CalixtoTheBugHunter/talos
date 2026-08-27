import Foundation
@testable import TalosAdapters

/// An ``AgentAdapter`` conformance driven entirely by the test that owns it —
/// no process, no CLI, no PATH probe, no conditional skip.
///
/// It is **not** a recorded fixture and not a stand-in for one. These suites
/// verify the shape of the contract, and nothing here parses agent output; the
/// committed real-capture fixtures
/// § The suite installs nothing requires belong to the first adapter that has a
/// parse to run them through.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-suite-installs-nothing
actor FakeAdapter: AgentAdapter {
    private var continuation: AgentEventStream.Continuation?
    private var usage: TokenReport
    private var lastOutput = ""
    private var hasTerminated = false

    /// What ``launch(_:)`` was handed, so a test can assert the working
    /// directory and environment crossed unchanged.
    private(set) var launchConfiguration: AgentLaunchConfiguration?
    /// Every prompt ``send(_:)`` transported, in order.
    private(set) var sentPrompts: [AgentPrompt] = []
    /// The decisions ``resolve(_:with:)`` carried back, by request id.
    private(set) var carriedDecisions: [String: AgentPermissionDecision] = [:]
    /// Permission requests emitted and not yet resolved.
    private(set) var openRequests: Set<String> = []

    init(usage: TokenReport = TestDefaults.usage) {
        self.usage = usage
    }

    // MARK: - The six capabilities

    func launch(_ configuration: AgentLaunchConfiguration) async throws -> AgentEventStream {
        launchConfiguration = configuration
        let (stream, continuation) = AgentEventStream.makeStream()
        self.continuation = continuation
        return stream
    }

    func send(_ prompt: AgentPrompt) async throws {
        guard continuation != nil, !hasTerminated else {
            throw AgentNotRunningError(fix: "Launch the adapter before sending a prompt.")
        }
        sentPrompts.append(prompt)
    }

    func resolve(_ requestID: AgentPermissionRequest.ID, with decision: AgentPermissionDecision) async throws {
        guard openRequests.contains(requestID) else {
            throw AgentNotRunningError(fix: "No permission request '\(requestID)' is waiting for a decision.")
        }
        openRequests.remove(requestID)
        carriedDecisions[requestID] = decision
    }

    func tokenUsage() async -> TokenReport {
        usage
    }

    func stop() async {
        finish(AgentTermination(reason: .stopped, lastOutput: lastOutput))
    }

    // MARK: - Driving it from a test

    /// Emits `event` on the stream, in order. A `terminated` event ends the
    /// run, exactly as a real one would.
    func emit(_ event: AgentEvent) {
        switch event {
        case let .output(chunk):
            lastOutput = chunk.text
        case let .permissionRequest(request):
            openRequests.insert(request.id)
        case .toolCall:
            break
        case let .terminated(termination):
            finish(termination)
            return
        }
        continuation?.yield(event)
    }

    /// Replaces what ``tokenUsage()`` reports — the drift case, which a test
    /// needs to reach after a run has already produced output.
    func setUsage(_ report: TokenReport) {
        usage = report
    }

    var isTerminated: Bool {
        hasTerminated
    }

    private func finish(_ termination: AgentTermination) {
        guard !hasTerminated else { return }
        hasTerminated = true
        continuation?.yield(.terminated(termination))
        continuation?.finish()
    }
}

/// What a fake run reports when the test does not care about the figures. The
/// counts are non-zero so a default report stays distinguishable from an absent
/// one, which is the distinction ``TokenReportTests`` exists to protect.
enum TestDefaults {
    static let inputTokens = 120
    static let outputTokens = 45
    static let usage = TokenReport.measured(
        TokenCounts(input: inputTokens, output: outputTokens),
        model: "test-model"
    )
}

/// A working directory and environment for a fake run. Deliberately holds no
/// credential of any kind.
enum TestLaunch {
    static func configuration() -> AgentLaunchConfiguration {
        AgentLaunchConfiguration(
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            environment: ["PATH": "/usr/bin:/bin"]
        )
    }
}
