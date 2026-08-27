import Foundation

/// Builds the argv for one Claude Code invocation. Every session is one or
/// more of these `claude` processes in sequence — headless, one prompt per
/// process — stitched into a single ``AgentEventStream`` by ``ClaudeCodeAdapter``.
///
/// Never a flag that suppresses or pre-approves its own prompts — that's
/// ``ClaudeCodeHookConfiguration``'s job.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
enum ClaudeCodeInvocation {
    /// Named rather than searched for here: ``ClaudeCodeInstallCheck`` resolves
    /// it against `PATH`, and `AgentProcess` takes only an absolute path.
    static let executableName = "claude"

    /// The flags shared by a first launch and a resume. `--setting-sources ""`
    /// loads no user or project settings, so `--settings` is the only source of
    /// hooks and nothing a project committed to `.claude/` runs unasked.
    private static let sharedFlags = [
        "-p",
        "--output-format", "stream-json",
        "--verbose",
        "--include-hook-events"
    ]

    static func launch(prompt: AgentPrompt, settingsPath: String, mcpConfigPath: String) -> [String] {
        sharedFlags + ["--setting-sources", "", "--settings", settingsPath] + mcpFlags(configPath: mcpConfigPath) +
            [prompt.text]
    }

    /// argv to resume `sessionID` with a new prompt, or with an empty one to
    /// carry a ``AgentAdapter/resolve(_:with:)`` decision back with nothing else
    /// to say.
    static func resume(
        sessionID: String, prompt: AgentPrompt, settingsPath: String, mcpConfigPath: String
    ) -> [String] {
        sharedFlags + ["--setting-sources", "", "--settings", settingsPath] + mcpFlags(configPath: mcpConfigPath) +
            ["--resume", sessionID, prompt.text]
    }

    /// `--strict-mcp-config` is what makes the pairing complete: without it,
    /// Claude Code still loads the project's own `.mcp.json` and the user's
    /// own configuration alongside whatever `--mcp-config` names, which is
    /// exactly the leak "only systems declared in `connectors.yaml` appear in
    /// generated config" forbids. Always passed, even for zero declared
    /// servers, so that case is suppressed too rather than left open.
    private static func mcpFlags(configPath: String) -> [String] {
        ["--mcp-config", configPath, "--strict-mcp-config"]
    }
}
