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

    /// The flags shared by a first launch and a resume.
    private static let sharedFlags = [
        "-p",
        "--output-format", "stream-json",
        "--verbose",
        "--include-hook-events"
    ]

    /// User settings only: the CLI's own authentication — a provider selection,
    /// a profile, a region — lives there, and a spawned CLI with no settings
    /// source has no credentials at all. Project and local stay excluded, so
    /// nothing a repository committed to `.claude/` runs unasked.
    /// § The CLI's own configuration is how it authenticates —
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
    private static let settingSourceFlags = ["--setting-sources", "user"]

    /// `--` ends the options, so a prompt is a prompt however it starts. An
    /// assembled prompt opens with the requesting guideline's own file, and
    /// those begin `---`, which the CLI otherwise reads as an unknown flag and
    /// exits on before the session begins.
    private static let endOfOptions = "--"

    static func launch(
        prompt: AgentPrompt, settingsPath: String, mcpConfigPath: String, model: String? = nil
    ) -> [String] {
        sharedFlags + settingSourceFlags + ["--settings", settingsPath] + mcpFlags(configPath: mcpConfigPath) +
            modelFlags(model) + [endOfOptions, prompt.text]
    }

    /// argv to resume `sessionID` with a new prompt, or with an empty one to
    /// carry a ``AgentAdapter/resolve(_:with:)`` decision back with nothing else
    /// to say.
    static func resume(
        sessionID: String, prompt: AgentPrompt, settingsPath: String, mcpConfigPath: String, model: String? = nil
    ) -> [String] {
        sharedFlags + settingSourceFlags + ["--settings", settingsPath] + mcpFlags(configPath: mcpConfigPath) +
            modelFlags(model) + ["--resume", sessionID, endOfOptions, prompt.text]
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

    /// `--model` when the project pinned one, and nothing otherwise so the
    /// launch is unchanged. This is where a pinned model takes effect: the
    /// settings file's own `model` key does not override the account default
    /// under `--setting-sources user` (verified against Claude Code 2.1.272),
    /// so the argv flag — which does — is the mechanism, per decision 91.
    /// It is a model *selection* handed to the CLI, never a permission mode,
    /// so it is unlike the flags this file otherwise refuses to pass.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
    private static func modelFlags(_ model: String?) -> [String] {
        model.map { ["--model", $0] } ?? []
    }
}
