@testable import TalosAdapters
import Testing

/// Asserts § How Talos finds you — the registry, and only the registry,
/// resolves the `adapter:` name, and each resolution is its own adapter.
/// > The registry, and only the registry [validates `adapter:`].
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
@Suite("Claude Code registration")
struct ClaudeCodeRegistrationTests {
    @Test("The registered name is 'claude-code', matching what Talos ships")
    func registeredNameIsClaudeCode() {
        #expect(ClaudeCodeAdapterRegistration.name == "claude-code")
    }

    @Test("Resolving 'claude-code' twice returns two distinct adapters")
    func eachResolutionIsFresh() throws {
        var registry = AgentAdapterRegistry()
        ClaudeCodeAdapterRegistration.register(into: &registry)

        let first = try registry.makeAdapter(named: "claude-code") as? ClaudeCodeAdapter
        let second = try registry.makeAdapter(named: "claude-code") as? ClaudeCodeAdapter

        #expect(first !== second)
    }

    @Test("An adapter resolved under 'claude-code' conforms to AgentAdapter")
    func resolvedAdapterConformsToTheProtocol() async throws {
        var registry = AgentAdapterRegistry()
        ClaudeCodeAdapterRegistration.register(into: &registry)

        let adapter = try registry.makeAdapter(named: "claude-code")
        let usage = await adapter.tokenUsage()
        #expect(usage == .unavailable(TokenUsageUnavailable(reason: .notReported)))
    }
}
