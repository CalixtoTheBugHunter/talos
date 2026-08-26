import Foundation
@testable import TalosAdapters
import Testing

/// Verifies ``AgentAdapterRegistry`` against
/// [Project Library § AI Agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#ai-agent) —
/// "Talos declares the agent, its adapter, its MCP servers, and its allowed
/// CLIs" — and the rule that an `agents.yaml` name is a public config contract.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives
@Suite("Agent adapter registry")
struct AgentAdapterRegistryTests {
    // MARK: - Resolution by the agents.yaml name (AC6)

    /// The key is the `adapter:` value as a user wrote it in
    /// `.talos/agents.yaml`.
    @Test("An adapter resolves by the name written in agents.yaml")
    func anAdapterResolvesByTheNameWrittenInAgentsYAML() throws {
        var registry = AgentAdapterRegistry()
        registry.register("some-agent-cli") { FakeAdapter() }

        let adapter = try registry.makeAdapter(named: "some-agent-cli")

        #expect(adapter is FakeAdapter)
    }

    /// Each resolution is its own adapter, because an adapter holds one run.
    @Test("Each resolution returns a fresh adapter")
    func eachResolutionReturnsAFreshAdapter() throws {
        var registry = AgentAdapterRegistry()
        registry.register("some-agent-cli") { FakeAdapter() }

        let first = try registry.makeAdapter(named: "some-agent-cli")
        let second = try registry.makeAdapter(named: "some-agent-cli")

        #expect(first as AnyObject !== second as AnyObject)
    }

    /// The name is matched exactly. A near-miss in a hand-written file is a
    /// failure the user can see, not a silent fallback to something else.
    @Test("A name that differs in case or spelling does not resolve")
    func aNameThatDiffersDoesNotResolve() throws {
        var registry = AgentAdapterRegistry()
        registry.register("some-agent-cli") { FakeAdapter() }

        #expect(throws: UnknownAdapterError.self) {
            try registry.makeAdapter(named: "Some-Agent-CLI")
        }
        #expect(throws: UnknownAdapterError.self) {
            try registry.makeAdapter(named: "some_agent_cli")
        }
    }

    // MARK: - An unknown name fails, naming the fix (AC6)

    /// The name came from a file a user edits by hand, so the failure names the
    /// value, the file, and what to change — the shape every `.talos/`
    /// validation failure uses.
    @Test("An unknown name throws an error naming the file, the value, and the fix")
    func anUnknownNameThrowsAnErrorNamingTheFix() throws {
        var registry = AgentAdapterRegistry()
        registry.register("some-agent-cli") { FakeAdapter() }

        let error = try #require(throws: UnknownAdapterError.self) {
            try registry.makeAdapter(named: "typo-cli")
        }
        #expect(error.name == "typo-cli")
        #expect(error.registeredNames == ["some-agent-cli"])
        #expect(error.fix.contains("agents.yaml"))
        #expect(error.fix.contains("some-agent-cli"))
    }

    /// Registered names are reported sorted, so the fix message lists them in a
    /// stable order rather than a dictionary's.
    @Test("Registered names are reported in a stable order")
    func registeredNamesAreReportedInAStableOrder() {
        var registry = AgentAdapterRegistry()
        registry.register("zulu-cli") { FakeAdapter() }
        registry.register("alpha-cli") { FakeAdapter() }

        #expect(registry.registeredNames == ["alpha-cli", "zulu-cli"])
    }

    // MARK: - No agent is known by default (AC6, AC7)

    /// A default would make one agent the answer to a name the user did not
    /// write, and it would put an agent's name in the registry — which is core.
    @Test("A fresh registry knows no adapter name")
    func aFreshRegistryKnowsNoAdapterName() {
        let registry = AgentAdapterRegistry()

        #expect(registry.registeredNames.isEmpty)
    }

    /// Nothing resolves before something registers, so no run can start against
    /// an adapter nobody wired up.
    @Test("A fresh registry resolves nothing")
    func aFreshRegistryResolvesNothing() {
        let registry = AgentAdapterRegistry()

        #expect(throws: UnknownAdapterError.self) {
            try registry.makeAdapter(named: "some-agent-cli")
        }
    }

    /// The failure with nothing registered still names a fix. Interpolating an
    /// empty list into the ordinary message yields "to one of: ." — a sentence
    /// that reads like a fix and names none, which is the one thing every
    /// `.talos/` validation failure owes.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice
    @Test("A fresh registry's failure names a fix rather than an empty list")
    func aFreshRegistryFailureNamesAFix() throws {
        let registry = AgentAdapterRegistry()

        let error = try #require(throws: UnknownAdapterError.self) {
            try registry.makeAdapter(named: "some-agent-cli")
        }
        #expect(error.registeredNames.isEmpty)
        #expect(!error.fix.contains("one of: ."))
        #expect(!error.fix.hasSuffix(": ."))
        #expect(error.fix.contains("some-agent-cli"))
        #expect(error.fix.contains("no adapter is registered at all"))
    }
}
