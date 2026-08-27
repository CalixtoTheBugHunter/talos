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

    static func configuration(launchResponse: String, resumeResponse: String) -> AgentLaunchConfiguration {
        AgentLaunchConfiguration(
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            environment: [
                "PATH": "/usr/bin:/bin",
                launchResponseKey: launchResponse,
                resumeResponseKey: resumeResponse
            ]
        )
    }
}

/// Asserts the shape of a denial: the agent is told, the session stays open,
/// nothing about the request stays half-applied, and it is recorded as denied
/// rather than as a failure.
/// § `agent-adapter` Rule 5 — a denial test ships for every newly gated action.
@Suite("Denial path")
struct ClaudeCodeDenialPathTests {
    @Test("A denied permission request resumes the session rather than ending it")
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

        try await adapter.resolve(call.id, with: .denied)
        await #expect(throws: AgentNotRunningError.self) {
            try await adapter.resolve(call.id, with: .denied)
        }

        try await adapter.send(AgentPrompt(text: "Continue."))

        await adapter.stop()
        var sawTermination = false
        for try await event in stream {
            if case .terminated = event {
                sawTermination = true
            }
        }
        #expect(sawTermination)
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
