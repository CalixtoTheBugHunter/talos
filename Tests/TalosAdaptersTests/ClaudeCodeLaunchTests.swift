@testable import TalosAdapters
import Testing

/// Asserts the argv this adapter builds never asks the CLI to suppress or
/// pre-approve its own prompts, and carries no credential of any kind — Talos
/// uses Claude Code's own existing authentication.
/// § An agent CLI's own permission prompt is never a Talos approval —
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
@Suite("Claude Code launch argv")
struct ClaudeCodeLaunchTests {
    static let forbiddenFlags = [
        "--dangerously-skip-permissions",
        "--allow-dangerously-skip-permissions",
        "--permission-mode",
        "bypassPermissions",
        "dontAsk",
        "acceptEdits"
    ]

    @Test("A first launch's argv names none of the forbidden permission modes", arguments: Self.forbiddenFlags)
    func launchArgvExcludesForbiddenFlags(flag: String) {
        let prompt = AgentPrompt(text: "hello")
        let arguments = ClaudeCodeInvocation.launch(
            prompt: prompt, settingsPath: "/tmp/settings.json", mcpConfigPath: "/tmp/mcp.json"
        )
        #expect(!arguments.contains(flag))
    }

    @Test("A resume's argv names none of the forbidden permission modes", arguments: Self.forbiddenFlags)
    func resumeArgvExcludesForbiddenFlags(flag: String) {
        let arguments = ClaudeCodeInvocation.resume(
            sessionID: "session-1",
            prompt: AgentPrompt(text: "hello"),
            settingsPath: "/tmp/settings.json",
            mcpConfigPath: "/tmp/mcp.json"
        )
        #expect(!arguments.contains(flag))
    }

    @Test("Nothing in the argv looks like a credential")
    func argvCarriesNoCredentialLookingValue() {
        let arguments = ClaudeCodeInvocation.resume(
            sessionID: "session-1",
            prompt: AgentPrompt(text: "hello"),
            settingsPath: "/tmp/settings.json",
            mcpConfigPath: "/tmp/mcp.json"
        )
        for argument in arguments {
            #expect(!argument.lowercased().contains("key"))
            #expect(!argument.lowercased().contains("token"))
            #expect(!argument.lowercased().contains("secret"))
        }
    }

    // MARK: - MCP config is always passed, and always strict (AC4)

    // "Only systems declared in connectors.yaml appear in generated config" —
    // without --strict-mcp-config, Claude Code would still load the project's
    // own .mcp.json and the user's own configuration alongside Talos's.
    // https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#connectors

    @Test("A first launch's argv names --mcp-config and --strict-mcp-config")
    func launchArgvNamesMCPFlags() {
        let arguments = ClaudeCodeInvocation.launch(
            prompt: AgentPrompt(text: "hello"), settingsPath: "/tmp/settings.json", mcpConfigPath: "/tmp/mcp.json"
        )
        #expect(arguments.contains("--strict-mcp-config"))
        guard let index = arguments.firstIndex(of: "--mcp-config") else {
            Issue.record("--mcp-config is missing from the argv")
            return
        }
        #expect(arguments[index + 1] == "/tmp/mcp.json")
    }

    @Test("A resume's argv names --mcp-config and --strict-mcp-config")
    func resumeArgvNamesMCPFlags() {
        let arguments = ClaudeCodeInvocation.resume(
            sessionID: "session-1",
            prompt: AgentPrompt(text: "hello"),
            settingsPath: "/tmp/settings.json",
            mcpConfigPath: "/tmp/mcp.json"
        )
        #expect(arguments.contains("--strict-mcp-config"))
        guard let index = arguments.firstIndex(of: "--mcp-config") else {
            Issue.record("--mcp-config is missing from the argv")
            return
        }
        #expect(arguments[index + 1] == "/tmp/mcp.json")
    }
}
