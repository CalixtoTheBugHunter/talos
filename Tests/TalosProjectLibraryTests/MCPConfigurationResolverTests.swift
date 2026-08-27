import Foundation
@testable import TalosCore
@testable import TalosProjectLibrary
import Testing

/// Verifies ``MCPConfigurationResolver`` generates MCP server configuration
/// **from `connectors.yaml`** — the second consequence of the orchestration
/// boundary — and that only a system `connectors.yaml` declares with
/// `reachedVia: mcp` ever appears in the result.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
@Suite("MCP configuration resolver")
struct MCPConfigurationResolverTests {
    private struct AllowingAuthorizer: SecretAccessAuthorizing {
        // swiftlint:disable:next no_empty_block
        func authorize(_: SecretAccessAction) throws {}
    }

    private static func freshProject() -> ProjectIdentifier {
        .generate()
    }

    private static func cleanUp(_ reference: SecretReference, project: ProjectIdentifier) {
        try? KeychainSecretAccessor(authorizer: AllowingAuthorizer()).delete(reference, project: project)
    }

    private static func connector(name: String, reachedVia: ConnectorAccessMethod) -> ConnectorDeclaration {
        ConnectorDeclaration(name: name, kind: .repo, target: "https://example.com/\(name)", reachedVia: reachedVia)
    }

    // MARK: - Only a system connectors.yaml declares with reachedVia: mcp appears (AC4)

    @Test("A server whose connector is declared reachedVia: cli is excluded")
    func aCLIConnectorIsExcluded() throws {
        let agent = AgentDeclaration(
            name: "claude-code",
            adapter: "claude-code",
            mcpServers: [MCPServerDeclaration(name: "github", command: "npx")]
        )
        let connectors = ConnectorsManifest(connectors: [Self.connector(name: "github", reachedVia: .cli)])

        let resolved = try MCPConfigurationResolver.resolve(
            agent: agent, connectors: connectors, project: Self.freshProject(),
            secrets: KeychainSecretAccessor(authorizer: AllowingAuthorizer())
        )

        #expect(resolved.isEmpty)
    }

    @Test("A server with no matching connector at all is excluded")
    func anUndeclaredServerIsExcluded() throws {
        let agent = AgentDeclaration(
            name: "claude-code",
            adapter: "claude-code",
            mcpServers: [MCPServerDeclaration(name: "github", command: "npx")]
        )
        let connectors = ConnectorsManifest(connectors: [])

        let resolved = try MCPConfigurationResolver.resolve(
            agent: agent, connectors: connectors, project: Self.freshProject(),
            secrets: KeychainSecretAccessor(authorizer: AllowingAuthorizer())
        )

        #expect(resolved.isEmpty)
    }

    @Test("A server declared reachedVia: mcp is kept, with its command and args intact")
    func anMCPConnectorIsKept() throws {
        let agent = AgentDeclaration(
            name: "claude-code",
            adapter: "claude-code",
            mcpServers: [
                MCPServerDeclaration(
                    name: "github", command: "npx", args: ["-y", "@modelcontextprotocol/server-github"]
                )
            ]
        )
        let connectors = ConnectorsManifest(connectors: [Self.connector(name: "github", reachedVia: .mcp)])

        let resolved = try MCPConfigurationResolver.resolve(
            agent: agent, connectors: connectors, project: Self.freshProject(),
            secrets: KeychainSecretAccessor(authorizer: AllowingAuthorizer())
        )

        #expect(resolved == [
            ResolvedMCPServerConfiguration(
                name: "github", command: "npx", args: ["-y", "@modelcontextprotocol/server-github"]
            )
        ])
    }

    // MARK: - Secret resolution (AC3)

    @Test("A literal env value passes through unchanged")
    func aLiteralEnvValuePassesThroughUnchanged() throws {
        let agent = AgentDeclaration(
            name: "claude-code",
            adapter: "claude-code",
            mcpServers: [
                MCPServerDeclaration(name: "github", command: "npx", env: ["NODE_ENV": .literal("production")])
            ]
        )
        let connectors = ConnectorsManifest(connectors: [Self.connector(name: "github", reachedVia: .mcp)])

        let resolved = try MCPConfigurationResolver.resolve(
            agent: agent, connectors: connectors, project: Self.freshProject(),
            secrets: KeychainSecretAccessor(authorizer: AllowingAuthorizer())
        )

        #expect(resolved.first?.env["NODE_ENV"] == .literal("production"))
    }

    @Test("A secret-referenced env value resolves to the value stored under it")
    func aSecretReferenceResolvesToTheStoredValue() throws {
        let reference = SecretReference(keychainName: "test-\(UUID().uuidString)")
        let project = Self.freshProject()
        let accessor = KeychainSecretAccessor(authorizer: AllowingAuthorizer())
        defer { Self.cleanUp(reference, project: project) }
        try accessor.write(reference, project: project, value: "ghp_the-real-value")

        let agent = AgentDeclaration(
            name: "claude-code",
            adapter: "claude-code",
            mcpServers: [
                MCPServerDeclaration(name: "github", command: "npx", env: ["GITHUB_TOKEN": .secret(reference)])
            ]
        )
        let connectors = ConnectorsManifest(connectors: [Self.connector(name: "github", reachedVia: .mcp)])

        let resolved = try MCPConfigurationResolver.resolve(
            agent: agent, connectors: connectors, project: project, secrets: accessor
        )

        #expect(resolved.first?.env["GITHUB_TOKEN"] == .secret("ghp_the-real-value"))
    }

    @Test("A missing secret throws rather than resolving to an empty value")
    func aMissingSecretThrows() throws {
        let reference = SecretReference(keychainName: "test-\(UUID().uuidString)")
        let agent = AgentDeclaration(
            name: "claude-code",
            adapter: "claude-code",
            mcpServers: [
                MCPServerDeclaration(name: "github", command: "npx", env: ["GITHUB_TOKEN": .secret(reference)])
            ]
        )
        let connectors = ConnectorsManifest(connectors: [Self.connector(name: "github", reachedVia: .mcp)])

        #expect(throws: MissingSecretError.self) {
            _ = try MCPConfigurationResolver.resolve(
                agent: agent, connectors: connectors, project: Self.freshProject(),
                secrets: KeychainSecretAccessor(authorizer: AllowingAuthorizer())
            )
        }
    }

    // MARK: - Idempotence (AC5)

    @Test("Resolving the same manifests twice produces equal results")
    func resolvingTwiceProducesEqualResults() throws {
        let reference = SecretReference(keychainName: "test-\(UUID().uuidString)")
        let project = Self.freshProject()
        let accessor = KeychainSecretAccessor(authorizer: AllowingAuthorizer())
        defer { Self.cleanUp(reference, project: project) }
        try accessor.write(reference, project: project, value: "ghp_the-real-value")

        let agent = AgentDeclaration(
            name: "claude-code",
            adapter: "claude-code",
            mcpServers: [
                MCPServerDeclaration(
                    name: "github", command: "npx", args: ["-y"],
                    env: ["GITHUB_TOKEN": .secret(reference), "NODE_ENV": .literal("production")]
                )
            ]
        )
        let connectors = ConnectorsManifest(connectors: [Self.connector(name: "github", reachedVia: .mcp)])

        let first = try MCPConfigurationResolver.resolve(
            agent: agent, connectors: connectors, project: project, secrets: accessor
        )
        let second = try MCPConfigurationResolver.resolve(
            agent: agent, connectors: connectors, project: project, secrets: accessor
        )

        #expect(first == second)
    }
}
