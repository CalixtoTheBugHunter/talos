import Foundation
import TalosCore

/// One resolved `env` value for a server ``MCPConfigurationResolver`` produced
/// — the plaintext a secret reference resolved to, kept distinct from an
/// ordinary literal so whichever layer writes the agent's own config file
/// never has to re-derive which case it is.
public enum ResolvedEnvValue: Equatable, Sendable {
    case literal(String)
    case secret(String)
}

/// One MCP server declared for an agent, filtered against `connectors.yaml`
/// and resolved against the Keychain — everything the adapter layer needs to
/// write that agent's own MCP config, and nothing it would need to look up
/// itself.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
public struct ResolvedMCPServerConfiguration: Equatable, Sendable {
    public let name: String
    public let command: String
    public let args: [String]
    public let env: [String: ResolvedEnvValue]

    public init(name: String, command: String, args: [String] = [], env: [String: ResolvedEnvValue] = [:]) {
        self.name = name
        self.command = command
        self.args = args
        self.env = env
    }
}

/// Generates MCP server configuration for an agent **from `connectors.yaml`**
/// — the second consequence of the orchestration boundary: "MCP servers are
/// configured *for the agent*; Talos writes that configuration and reads its
/// results."
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
///
/// `agents.yaml` already carries each MCP server's full launch shape —
/// command, args, env. This resolver's own job is narrower: keep only the
/// servers whose name is **declared** in `connectors.yaml` with
/// `reachedVia: mcp`, per
/// [Project Library § Connectors](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#connectors) —
/// "Any action against a system not declared in `connectors.yaml` is never
/// allowlistable" — and resolve each server's secret-shaped `env` values
/// against the Keychain, so nothing downstream reads `agents.yaml` a second
/// time to get a value this layer already has.
public enum MCPConfigurationResolver {
    /// Resolves `agent`'s declared MCP servers, keeping only those `connectors`
    /// also declares with `reachedVia: mcp` — a server named in `agents.yaml`
    /// but absent from `connectors.yaml`, or declared there as `cli`, is
    /// silently excluded rather than reported, the same discipline
    /// `ConnectorsManifest.isDeclared` uses for an undeclared system.
    ///
    /// - Throws: Whatever ``KeychainSecretAccessor/read(_:project:)`` throws
    ///   for a secret reference that is missing or denied — this function
    ///   resolves eagerly rather than deferring the failure to whoever reads
    ///   the result.
    public static func resolve(
        agent: AgentDeclaration,
        connectors: ConnectorsManifest,
        project: ProjectIdentifier,
        secrets: KeychainSecretAccessor
    ) throws -> [ResolvedMCPServerConfiguration] {
        try agent.mcpServers
            .filter { server in isDeclaredForMCP(server.name, in: connectors) }
            .map { server in try resolve(server: server, project: project, secrets: secrets) }
    }

    private static func isDeclaredForMCP(_ name: String, in connectors: ConnectorsManifest) -> Bool {
        connectors.connectors.contains { $0.name == name && $0.reachedVia == .mcp }
    }

    private static func resolve(
        server: MCPServerDeclaration,
        project: ProjectIdentifier,
        secrets: KeychainSecretAccessor
    ) throws -> ResolvedMCPServerConfiguration {
        var env: [String: ResolvedEnvValue] = [:]
        for (key, value) in server.env {
            switch value {
            case let .literal(literal):
                env[key] = .literal(literal)
            case let .secret(reference):
                env[key] = try .secret(secrets.read(reference, project: project))
            }
        }
        return ResolvedMCPServerConfiguration(name: server.name, command: server.command, args: server.args, env: env)
    }
}
