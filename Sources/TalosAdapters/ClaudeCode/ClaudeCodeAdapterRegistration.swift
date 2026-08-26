import Foundation

// The public entry point that registers this adapter. Nothing in `Sources/`
// calls `AgentAdapterRegistry.register` otherwise, so without this the
// registry resolves no adapters at all.
// § "The registry, and only the registry [validates `adapter:`]" — Decision 72
// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#the-agentsyaml-shape

/// Where a build registers this adapter, so `.talos/agents.yaml`'s `adapter:`
/// value can resolve to it.
public enum ClaudeCodeAdapterRegistration {
    /// The `adapter:` value `.talos/agents.yaml` names to select this adapter —
    /// "Talos ships `claude-code`", per the page above.
    public static let name = "claude-code"

    /// Registers a fresh ``ClaudeCodeAdapter`` factory under ``name``.
    public static func register(into registry: inout AgentAdapterRegistry) {
        registry.register(name) { ClaudeCodeAdapter() }
    }
}
