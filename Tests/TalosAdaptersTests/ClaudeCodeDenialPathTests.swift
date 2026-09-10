import Foundation
@testable import TalosAdapters
import Testing

/// A stand-in for the `claude` binary: a shell script that answers with a
/// canned fixture, chosen by whether `--resume` is in its own argv. Lets a
/// test drive ``ClaudeCodeAdapter`` through a real spawn without the real CLI
/// installed — § The suite installs nothing.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-suite-installs-nothing
enum ClaudeCodeFakeExecutable {
    private static let launchResponseKey = "TALOS_TEST_LAUNCH_RESPONSE"
    private static let resumeResponseKey = "TALOS_TEST_RESUME_RESPONSE"

    /// `exitCode` is baked into every branch of the script, for the one test
    /// that needs to simulate a crash rather than Claude Code's own normal
    /// clean exit.
    static func write(exitCode: Int32 = 0) throws -> String {
        let path = NSTemporaryDirectory() + "talos-claude-code-fake-\(UUID().uuidString)"
        let script = """
        #!/bin/sh
        for arg in "$@"; do
          if [ "$arg" = "--resume" ]; then
            cat "$\(resumeResponseKey)"
            exit \(exitCode)
          fi
        done
        cat "$\(launchResponseKey)"
        exit \(exitCode)
        """
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    static func configuration(
        launchResponse: String,
        resumeResponse: String,
        resumeToken: String? = nil
    ) -> AgentLaunchConfiguration {
        AgentLaunchConfiguration(
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            environment: [
                "PATH": "/usr/bin:/bin",
                launchResponseKey: launchResponse,
                resumeResponseKey: resumeResponse
            ],
            resumeToken: resumeToken
        )
    }
}

/// Asserts the shape of a denial: the agent is told, the session stays open,
/// nothing about the request stays half-applied, and it is recorded as denied
/// rather than as a failure.
/// § `agent-adapter` Rule 5 — a denial test ships for every newly gated action.
@Suite("Denial path")
struct ClaudeCodeDenialPathTests {
    @Test("A denied permission request resumes the session, which then ends on its own clean exit")
    func denialResumesRatherThanEnding() async throws {
        let executablePath = try ClaudeCodeFakeExecutable.write()
        let configuration = ClaudeCodeFakeExecutable.configuration(
            launchResponse: ClaudeCodeFixture.path("both-together.jsonl"),
            resumeResponse: ClaudeCodeFixture.path("token-report.jsonl")
        )
        let adapter = ClaudeCodeAdapter(executableOverride: executablePath)
        let stream = try await adapter.launch(configuration)

        try await adapter.send(AgentPrompt(text: "Write a file."))

        var iterator = stream.makeAsyncIterator()
        guard case let .toolCall(call) = try await iterator.next() else {
            Issue.record("Expected a tool call first")
            return
        }
        guard case .permissionRequest = try await iterator.next() else {
            Issue.record("Expected a permission request second")
            return
        }

        // The denial is carried back and the session resumes rather than ending
        // — "a denial is a normal outcome... the agent is told it was denied and
        // continues." The resumed turn then exits cleanly with nothing pending,
        // which ends the session on its own — no external `stop()` (Decision 80).
        try await adapter.resolve(call.id, with: .denied)
        await #expect(throws: AgentNotRunningError.self) {
            try await adapter.resolve(call.id, with: .denied)
        }

        var sawTermination = false
        while let event = try await iterator.next() {
            if case let .terminated(termination) = event {
                #expect(termination.reason == .exited(code: 0))
                sawTermination = true
            }
        }
        #expect(sawTermination)
    }
}

/// Asserts the counterpart to an abnormal exit: a clean exit with no pending
/// permission ends the session on its own, with no external `stop()`, emitting
/// the terminating `.exited(0)` the pipeline records as succeeded.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
@Suite("Clean exit")
struct ClaudeCodeCleanExitTests {
    @Test("A clean exit with no pending permission ends the session without an external stop")
    func cleanExitEndsTheSession() async throws {
        let executablePath = try ClaudeCodeFakeExecutable.write()
        let configuration = ClaudeCodeFakeExecutable.configuration(
            launchResponse: ClaudeCodeFixture.path("tool-call.jsonl"),
            resumeResponse: ClaudeCodeFixture.path("tool-call.jsonl")
        )
        let adapter = ClaudeCodeAdapter(executableOverride: executablePath)
        let stream = try await adapter.launch(configuration)

        try await adapter.send(AgentPrompt(text: "What does the README say?"))

        var events: [AgentEvent] = []
        for try await event in stream {
            events.append(event)
        }

        guard case .toolCall = events.first, case let .terminated(termination) = events.last else {
            Issue.record("Expected [toolCall, ..., terminated], got \(events)")
            return
        }
        #expect(termination.reason == .exited(code: 0))
    }
}

/// Asserts a crashed turn ends the session rather than being absorbed like an
/// ordinary end of turn — only a clean exit is.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#errors
@Suite("Abnormal exit")
struct ClaudeCodeAbnormalExitTests {
    @Test("A nonzero exit ends the session, carrying the agent's own last output")
    func nonZeroExitEndsTheSession() async throws {
        let executablePath = try ClaudeCodeFakeExecutable.write(exitCode: 1)
        let configuration = ClaudeCodeFakeExecutable.configuration(
            launchResponse: ClaudeCodeFixture.path("abnormal-exit.jsonl"),
            resumeResponse: ClaudeCodeFixture.path("abnormal-exit.jsonl")
        )
        let adapter = ClaudeCodeAdapter(executableOverride: executablePath)
        let stream = try await adapter.launch(configuration)

        try await adapter.send(AgentPrompt(text: "Write a file."))

        var termination: AgentTermination?
        for try await event in stream {
            if case let .terminated(value) = event {
                termination = value
            }
        }

        #expect(termination?.reason == .exited(code: 1))
    }
}
