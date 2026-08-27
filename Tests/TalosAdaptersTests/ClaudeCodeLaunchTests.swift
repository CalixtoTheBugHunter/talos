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
        let arguments = ClaudeCodeInvocation.launch(prompt: prompt, settingsPath: "/tmp/settings.json")
        #expect(!arguments.contains(flag))
    }

    @Test("A resume's argv names none of the forbidden permission modes", arguments: Self.forbiddenFlags)
    func resumeArgvExcludesForbiddenFlags(flag: String) {
        let arguments = ClaudeCodeInvocation.resume(
            sessionID: "session-1",
            prompt: AgentPrompt(text: "hello"),
            settingsPath: "/tmp/settings.json"
        )
        #expect(!arguments.contains(flag))
    }

    @Test("Nothing in the argv looks like a credential")
    func argvCarriesNoCredentialLookingValue() {
        let arguments = ClaudeCodeInvocation.resume(
            sessionID: "session-1",
            prompt: AgentPrompt(text: "hello"),
            settingsPath: "/tmp/settings.json"
        )
        for argument in arguments {
            #expect(!argument.lowercased().contains("key"))
            #expect(!argument.lowercased().contains("token"))
            #expect(!argument.lowercased().contains("secret"))
        }
    }
}
