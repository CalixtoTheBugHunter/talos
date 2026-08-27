import Foundation

/// Writes Claude Code's own `--mcp-config` JSON for one session, into a
/// directory this adapter owns — never `.mcp.json` at the project root, so
/// regenerating it never clobbers whatever a user or the project already
/// committed there.
///
/// Always written, even with zero servers: paired with `--strict-mcp-config`
/// on the invocation, an empty `mcpServers` object still needs a file to
/// point the flag at, and that pairing is what keeps the project's and the
/// user's own MCP configuration from reaching the agent when Talos declared
/// none.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
struct ClaudeCodeMCPConfiguration: Sendable {
    /// Passed to `--mcp-config` on every `claude` invocation this session runs.
    let configPath: String
    private let directory: URL

    init(
        servers: [MCPServerLaunchConfiguration],
        rootDirectory: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    ) throws {
        directory = rootDirectory
            .appendingPathComponent("talos-claude-code-mcp-\(UUID().uuidString)", isDirectory: true)
        let configURL = directory.appendingPathComponent("mcp.json")
        configPath = configURL.path

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = RootConfiguration(mcpServers: Self.serverEntries(for: servers))
        try Self.encoder.encode(root).write(to: configURL, options: .atomic)
    }

    /// Removes everything this session wrote, once the run has ended.
    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// `.sortedKeys` is what makes two calls with the same input byte-identical
    /// — dictionary iteration order is otherwise unspecified, and this is what
    /// "regenerating the config is idempotent" means for a written file.
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private struct RootConfiguration: Encodable {
        let mcpServers: [String: ServerConfiguration]
    }

    private struct ServerConfiguration: Encodable {
        let command: String
        let args: [String]
        let env: [String: String]
    }

    /// Later entries win over earlier ones with the same name, rather than
    /// trapping: a name collision in `agents.yaml` is a validation question
    /// for `TalosProjectLibrary`, not a reason for this layer to crash on
    /// whatever it was handed.
    private static func serverEntries(for servers: [MCPServerLaunchConfiguration]) -> [String: ServerConfiguration] {
        var entries: [String: ServerConfiguration] = [:]
        for server in servers {
            entries[server.name] = ServerConfiguration(
                command: server.command, args: server.args, env: environment(for: server.env)
            )
        }
        return entries
    }

    /// A literal is written verbatim; a secret reference is written as
    /// Claude Code's own `${NAME}` expansion syntax — never the value it
    /// stands for, which lives only in the process environment this session's
    /// child receives.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#secret-references-never-secrets
    private static func environment(for values: [String: MCPServerEnvironmentValue]) -> [String: String] {
        values.mapValues { value in
            switch value {
            case let .literal(literal):
                literal
            case let .secretReference(name):
                "${\(name)}"
            }
        }
    }
}
