import Foundation
@testable import TalosAdapters
import Testing

/// Verifies the JSON this adapter writes for Claude Code's own `--mcp-config`
/// flag: it never inlines a secret value, it carries only the servers it was
/// given, regenerating it is deterministic, and writing it never touches a
/// project's own `.mcp.json`.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
@Suite("Claude Code MCP configuration")
struct ClaudeCodeMCPConfigurationTests {
    static func fileContents(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    // MARK: - A secret reference is never inlined (AC3)

    @Test("A secret-referenced env value is written as Claude Code's own expansion syntax, never the value")
    func aSecretReferenceIsWrittenAsExpansionSyntaxNeverTheValue() throws {
        let servers = [
            MCPServerLaunchConfiguration(
                name: "github",
                command: "npx",
                env: ["GITHUB_TOKEN": .secretReference(name: "GITHUB_TOKEN")]
            )
        ]
        let configuration = try ClaudeCodeMCPConfiguration(servers: servers)
        defer { configuration.cleanUp() }

        let contents = try Self.fileContents(configuration.configPath)

        #expect(contents.contains("${GITHUB_TOKEN}"))
        #expect(!contents.contains("ghp_the-real-secret-value"))
    }

    @Test("A literal env value is written verbatim")
    func aLiteralEnvValueIsWrittenVerbatim() throws {
        let servers = [
            MCPServerLaunchConfiguration(name: "github", command: "npx", env: ["NODE_ENV": .literal("production")])
        ]
        let configuration = try ClaudeCodeMCPConfiguration(servers: servers)
        defer { configuration.cleanUp() }

        let contents = try Self.fileContents(configuration.configPath)

        #expect(contents.contains("\"NODE_ENV\":\"production\""))
    }

    // MARK: - Only the servers it was given appear (AC4)

    @Test("Only the servers passed in appear in the written config")
    func onlyThePassedInServersAppear() throws {
        let servers = [MCPServerLaunchConfiguration(name: "github", command: "npx")]
        let configuration = try ClaudeCodeMCPConfiguration(servers: servers)
        defer { configuration.cleanUp() }

        let data = try Data(contentsOf: URL(fileURLWithPath: configuration.configPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let mcpServers = json?["mcpServers"] as? [String: Any]

        #expect(mcpServers?.count == 1)
        #expect(mcpServers?["github"] != nil)
    }

    @Test("Zero declared servers still writes a config with an empty server map")
    func zeroDeclaredServersStillWritesAnEmptyConfig() throws {
        let configuration = try ClaudeCodeMCPConfiguration(servers: [])
        defer { configuration.cleanUp() }

        let data = try Data(contentsOf: URL(fileURLWithPath: configuration.configPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect((json?["mcpServers"] as? [String: Any])?.isEmpty == true)
    }

    // MARK: - Idempotence (AC5)

    @Test("Regenerating the config from the same input produces byte-identical output")
    func regeneratingFromTheSameInputProducesByteIdenticalOutput() throws {
        let servers = [
            MCPServerLaunchConfiguration(
                name: "github",
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-github"],
                env: ["GITHUB_TOKEN": .secretReference(name: "GITHUB_TOKEN"), "NODE_ENV": .literal("production")]
            )
        ]

        let first = try ClaudeCodeMCPConfiguration(servers: servers)
        defer { first.cleanUp() }
        let second = try ClaudeCodeMCPConfiguration(servers: servers)
        defer { second.cleanUp() }

        #expect(try Self.fileContents(first.configPath) == Self.fileContents(second.configPath))
    }

    // MARK: - Never clobbers unrelated user MCP config (AC5)

    @Test("Writing the config never touches a project's own .mcp.json")
    func writingNeverTouchesAProjectsOwnMCPJSON() throws {
        let projectDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("talos-test-project-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectDirectory) }

        let userMCPConfig = projectDirectory.appendingPathComponent(".mcp.json")
        let sentinel = #"{"mcpServers":{"user-declared":{"command":"whatever-the-user-already-committed"}}}"#
        try sentinel.write(to: userMCPConfig, atomically: true, encoding: .utf8)

        let configuration = try ClaudeCodeMCPConfiguration(
            servers: [MCPServerLaunchConfiguration(name: "github", command: "npx")],
            rootDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        )
        defer { configuration.cleanUp() }

        #expect(try Self.fileContents(userMCPConfig.path) == sentinel)
        #expect(configuration.configPath != userMCPConfig.path)
    }
}
