import Foundation

// The typed model for `.talos/agents.yaml` — agent adapters, their MCP
// servers, and their allowed CLIs. Secret fields hold only a reference to a
// Keychain entry, never a secret.
// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#the-agentsyaml-shape
// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#secret-references-never-secrets
//
// https://github.com/CalixtoTheBugHunter/talos/issues/43

/// The registered agent adapters, per
/// [Architecture: The Orchestration Boundary § Agent
/// adapters](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#agent-adapters).
/// This is the set `AgentsManifestParser` validates an `adapter:` name
/// against — an adapter is a thin layer under `TalosAdapters`, but the name
/// a project's `agents.yaml` may reference is fixed regardless of whether
/// that adapter has landed yet.
public enum AdapterKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case claudeCode = "claude-code"
    case geminiCLI = "gemini-cli"
    case codexCLI = "codex-cli"
    case ollama
}

/// A reference to a secret held in the macOS Keychain — `keychain:<name>` in
/// `agents.yaml`. `name` is resolved against a fixed Keychain convention
/// (service `"Talos"`, account `name`); it never carries the secret itself.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
public struct SecretReference: Equatable, Hashable, Sendable {
    public let keychainName: String

    public init(keychainName: String) {
        self.keychainName = keychainName
    }
}

/// One `env` value under an MCP server declaration: either a reference to a
/// secret, or an ordinary non-secret literal (`NODE_ENV: production`).
/// `AgentsManifestParser` is what decides which one a given value is, and
/// rejects a literal that looks like a secret rather than modeling it here.
public enum EnvValue: Equatable, Hashable, Sendable {
    case secret(SecretReference)
    case literal(String)
}

/// One MCP server this agent runs with.
public struct MCPServerDeclaration: Equatable, Sendable {
    public let name: String
    public let command: String
    public let args: [String]
    public let env: [String: EnvValue]

    public init(name: String, command: String, args: [String] = [], env: [String: EnvValue] = [:]) {
        self.name = name
        self.command = command
        self.args = args
        self.env = env
    }
}

/// One agent declared in `agents.yaml`, keyed by `name` in the file — the
/// same name `project.yaml`'s own `agents:` list references.
public struct AgentDeclaration: Equatable, Sendable {
    public let name: String
    public let adapter: AdapterKind
    public let mcpServers: [MCPServerDeclaration]
    public let allowedCLIs: [String]

    public init(
        name: String,
        adapter: AdapterKind,
        mcpServers: [MCPServerDeclaration] = [],
        allowedCLIs: [String] = []
    ) {
        self.name = name
        self.adapter = adapter
        self.mcpServers = mcpServers
        self.allowedCLIs = allowedCLIs
    }
}

/// The parsed, validated contents of `.talos/agents.yaml`. More than one
/// agent may be declared, per
/// [Project Library § AI Agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#ai-agent):
/// "More than one agent may be configured, and Talos orchestrates the use of
/// each."
public struct AgentsManifest: Equatable, Sendable {
    public let agents: [AgentDeclaration]

    public init(agents: [AgentDeclaration] = []) {
        self.agents = agents
    }
}

/// A validation failure that names the file, the line, and the fix — the
/// same shape ``ProjectManifestError`` uses for `project.yaml`. A failure
/// naming a secret-shaped `env` value never includes the value itself, only
/// the key: the message that reports a pasted secret must not echo it back.
public struct AgentsManifestError: Error, Equatable, Sendable {
    /// The path of the file that failed to parse or validate.
    public let file: String
    /// The 1-indexed source line the failure was found at, when the YAML
    /// parser could locate one.
    public let line: Int?
    /// What to change to fix it, stated as an instruction.
    public let fix: String
}
