import Foundation
import TalosCore
import Yams

/// Parses `.talos/agents.yaml` against ``AgentsManifest``.
///
/// All `Yams` usage is contained to this one file, the same discipline
/// `ProjectManifestParser` uses for `project.yaml` — the rest of Talos sees
/// only ``AgentsManifest``.
///
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#the-agentsyaml-shape
/// https://github.com/CalixtoTheBugHunter/talos/issues/43
public enum AgentsManifestParser {
    private static let agentsKey = "agents"
    private static let adapterKey = "adapter"
    private static let mcpServersKey = "mcpServers"
    private static let allowedCLIsKey = "allowedCLIs"
    private static let nameKey = "name"
    private static let commandKey = "command"
    private static let argsKey = "args"
    private static let envKey = "env"

    /// Parses `contents` as `.talos/agents.yaml`. `file` is only used to
    /// label a thrown ``AgentsManifestError`` — this function does no
    /// filesystem access of its own.
    public static func parse(contents: String, file: String) throws -> AgentsManifest {
        let mapping = try rootMapping(of: contents, file: file)
        return try AgentsManifest(agents: parseAgents(mapping: mapping, file: file))
    }

    // MARK: - Parsing, one field at a time

    /// Composes `contents` and returns its top-level mapping, or throws an
    /// ``AgentsManifestError`` naming the line a syntax error or a
    /// non-mapping root was found at.
    private static func rootMapping(of contents: String, file: String) throws -> Node.Mapping {
        let root: Node
        do {
            guard let node = try Yams.compose(yaml: contents) else {
                return [:]
            }
            root = node
        } catch {
            throw AgentsManifestError(file: file, line: sourceLine(of: error), fix: "Fix the YAML syntax: \(error)")
        }

        guard let mapping = root.mapping else {
            throw AgentsManifestError(
                file: file,
                line: root.mark?.line,
                fix: "The top level of '\(file)' must be a YAML mapping, not a scalar or a sequence."
            )
        }
        return mapping
    }

    private static func parseAgents(mapping: Node.Mapping, file: String) throws -> [AgentDeclaration] {
        guard let agentsNode = mapping[agentsKey] else { return [] }
        guard let agentsMapping = agentsNode.mapping else {
            throw AgentsManifestError(
                file: file,
                line: agentsNode.mark?.line,
                fix: "'\(agentsKey)' must be a YAML mapping, keyed by agent name."
            )
        }

        return try agentsMapping.map { key, value in
            guard let name = key.string, !name.isEmpty else {
                throw AgentsManifestError(
                    file: file,
                    line: key.mark?.line,
                    fix: "Every key under '\(agentsKey)' must be a non-empty string naming an agent."
                )
            }
            return try parseAgent(name: name, node: value, file: file)
        }
    }

    private static func parseAgent(name: String, node: Node, file: String) throws -> AgentDeclaration {
        guard let agentMapping = node.mapping else {
            throw AgentsManifestError(
                file: file,
                line: node.mark?.line,
                fix: "'\(agentsKey).\(name)' must be a YAML mapping with an '\(adapterKey)' key."
            )
        }

        return try AgentDeclaration(
            name: name,
            adapter: parseAdapter(agentName: name, mapping: agentMapping, file: file),
            mcpServers: parseMCPServers(agentName: name, mapping: agentMapping, file: file),
            allowedCLIs: parseAllowedCLIs(agentName: name, mapping: agentMapping, file: file)
        )
    }

    private static func parseAdapter(agentName: String, mapping: Node.Mapping, file: String) throws -> AdapterKind {
        guard let adapterNode = mapping[adapterKey], let rawValue = adapterNode.string else {
            throw AgentsManifestError(
                file: file,
                line: mapping.mark?.line,
                fix: "'\(agentsKey).\(agentName)' is missing a required '\(adapterKey)' string."
            )
        }
        guard let adapter = AdapterKind(rawValue: rawValue) else {
            let registered = AdapterKind.allCases.map(\.rawValue).joined(separator: ", ")
            throw AgentsManifestError(
                file: file,
                line: adapterNode.mark?.line,
                fix: "'\(rawValue)' is not a registered adapter. Use one of: \(registered)."
            )
        }
        return adapter
    }

    private static func parseMCPServers(
        agentName: String,
        mapping: Node.Mapping,
        file: String
    ) throws -> [MCPServerDeclaration] {
        guard let serversNode = mapping[mcpServersKey] else { return [] }
        guard let sequence = serversNode.sequence else {
            throw AgentsManifestError(
                file: file,
                line: serversNode.mark?.line,
                fix: "'\(agentsKey).\(agentName).\(mcpServersKey)' must be a YAML sequence."
            )
        }
        return try sequence.map { try parseMCPServer(agentName: agentName, node: $0, file: file) }
    }

    private static func parseMCPServer(agentName: String, node: Node, file: String) throws -> MCPServerDeclaration {
        guard let serverMapping = node.mapping else {
            throw AgentsManifestError(
                file: file,
                line: node.mark?.line,
                fix: "Every '\(agentsKey).\(agentName).\(mcpServersKey)' entry must be a YAML mapping."
            )
        }

        guard let name = serverMapping[nameKey]?.string, !name.isEmpty else {
            throw AgentsManifestError(
                file: file,
                line: serverMapping.mark?.line,
                fix: "Every '\(mcpServersKey)' entry needs a non-empty '\(nameKey)' string."
            )
        }
        guard let command = serverMapping[commandKey]?.string, !command.isEmpty else {
            throw AgentsManifestError(
                file: file,
                line: serverMapping.mark?.line,
                fix: "'\(mcpServersKey).\(name)' needs a non-empty '\(commandKey)' string."
            )
        }

        let path = "\(agentsKey).\(agentName).\(mcpServersKey)[\(name)]"
        return try MCPServerDeclaration(
            name: name,
            command: command,
            args: parseArgs(serverName: name, mapping: serverMapping, file: file),
            env: parseEnv(path: path, mapping: serverMapping, file: file)
        )
    }

    private static func parseArgs(serverName: String, mapping: Node.Mapping, file: String) throws -> [String] {
        guard let argsNode = mapping[argsKey] else { return [] }
        guard let sequence = argsNode.sequence else {
            throw AgentsManifestError(
                file: file,
                line: argsNode.mark?.line,
                fix: "'\(mcpServersKey).\(serverName).\(argsKey)' must be a YAML sequence of strings."
            )
        }
        return try sequence.map { element in
            guard let value = element.string else {
                throw AgentsManifestError(
                    file: file,
                    line: element.mark?.line,
                    fix: "Every '\(mcpServersKey).\(serverName).\(argsKey)' entry must be a string."
                )
            }
            return value
        }
    }

    /// `path` is the dotted location of the MCP server this `env` mapping
    /// belongs to (for example `agents.claude-code.mcpServers[github]`), so
    /// every value's error can name exactly where it was found.
    private static func parseEnv(path: String, mapping: Node.Mapping, file: String) throws -> [String: EnvValue] {
        guard let envNode = mapping[envKey] else { return [:] }
        guard let envMapping = envNode.mapping else {
            throw AgentsManifestError(
                file: file,
                line: envNode.mark?.line,
                fix: "'\(path).\(envKey)' must be a YAML mapping."
            )
        }

        var env: [String: EnvValue] = [:]
        for (keyNode, valueNode) in envMapping {
            guard let key = keyNode.string, !key.isEmpty else {
                throw AgentsManifestError(
                    file: file,
                    line: keyNode.mark?.line,
                    fix: "Every key under '\(path).\(envKey)' must be a non-empty string."
                )
            }
            guard let value = valueNode.string else {
                throw AgentsManifestError(
                    file: file,
                    line: valueNode.mark?.line,
                    fix: "'\(path).\(envKey).\(key)' must be a string — a literal value or a " +
                        "'\(EnvSecretHeuristics.keychainPrefix)<name>' reference."
                )
            }
            env[key] = try parseEnvValue(
                path: "\(path).\(envKey)", key: key, value: value, line: valueNode.mark?.line, file: file
            )
        }
        return env
    }

    private static func parseEnvValue(
        path: String,
        key: String,
        value: String,
        line: Int?,
        file: String
    ) throws -> EnvValue {
        if value.hasPrefix(EnvSecretHeuristics.keychainPrefix) {
            let name = String(value.dropFirst(EnvSecretHeuristics.keychainPrefix.count))
            guard !name.isEmpty else {
                throw AgentsManifestError(
                    file: file,
                    line: line,
                    fix: "'\(path).\(key)' has an empty Keychain reference — use " +
                        "'\(EnvSecretHeuristics.keychainPrefix)<name>'."
                )
            }
            return .secret(SecretReference(keychainName: name))
        }

        if let reason = EnvSecretHeuristics.literalSecretReason(key: key, value: value) {
            throw AgentsManifestError(
                file: file,
                line: line,
                fix: "'\(path).\(key)' \(reason) — use a Keychain reference " +
                    "'\(EnvSecretHeuristics.keychainPrefix)<name>' instead of a literal value."
            )
        }
        return .literal(value)
    }

    private static func parseAllowedCLIs(agentName: String, mapping: Node.Mapping, file: String) throws -> [String] {
        guard let cliNode = mapping[allowedCLIsKey] else { return [] }
        guard let sequence = cliNode.sequence else {
            throw AgentsManifestError(
                file: file,
                line: cliNode.mark?.line,
                fix: "'\(agentsKey).\(agentName).\(allowedCLIsKey)' must be a YAML sequence of strings."
            )
        }
        return try sequence.map { element in
            guard let value = element.string else {
                throw AgentsManifestError(
                    file: file,
                    line: element.mark?.line,
                    fix: "Every '\(allowedCLIsKey)' entry must be a string naming a CLI binary."
                )
            }
            return value
        }
    }

    /// The line a composer/parser/scanner `YamlError` points at, when it
    /// carries one.
    private static func sourceLine(of error: Error) -> Int? {
        guard let yamlError = error as? YamlError else { return nil }
        switch yamlError {
        case let .scanner(_, _, mark, _), let .parser(_, _, mark, _), let .composer(_, _, mark, _):
            return mark.line
        default:
            return nil
        }
    }
}

/// What makes a literal `env` value one `AgentsManifestParser` must reject —
/// kept as its own type so `AgentsManifestParser`'s own body stays about
/// parsing YAML shape, not about what a secret looks like.
///
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#secret-references-never-secrets
private enum EnvSecretHeuristics {
    /// The prefix a `env` value must carry to be a Keychain reference
    /// rather than a literal.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
    static let keychainPrefix = "keychain:"

    /// Case-insensitive substrings in an `env` key name that mark it as a
    /// field expected to hold a credential. A key matching one of these may
    /// never hold a literal, regardless of what the literal looks like.
    private static let secretKeyNameHints = ["token", "secret", "password", "credential", "key", "auth"]

    /// A literal must be at least this long before the generic high-entropy
    /// check considers it — shorter strings are ordinary words and flags.
    private static let minimumHighEntropyLength = 20

    /// Above this many bits of Shannon entropy per character, a literal is
    /// treated as secret-shaped. Chosen so a hex or UUID-shaped identifier
    /// (at most 4.0 bits/char over its 16-symbol alphabet) is not flagged.
    private static let highEntropyThreshold = 4.0

    /// Why a literal `env` value at `key` must be a Keychain reference
    /// instead, or `nil` when the literal is ordinary configuration. Never
    /// includes `value` itself in the returned reason — the message that
    /// reports a pasted secret must not echo it back.
    static func literalSecretReason(key: String, value: String) -> String? {
        let lowercasedKey = key.lowercased()
        if let hint = secretKeyNameHints.first(where: { lowercasedKey.contains($0) }) {
            return "names what looks like a credential (contains '\(hint)')"
        }
        if LogRedaction.redacted(value) != value {
            return "holds a literal value shaped like a known credential"
        }
        if isHighEntropyLiteral(value) {
            return "holds a long, high-entropy literal value shaped like a secret"
        }
        return nil
    }

    /// A literal with no recognized credential shape can still be one — a
    /// long, high-entropy run with no recognizable prefix. Requires a
    /// minimum length and a mix of letters and digits so an ordinary word,
    /// sentence, or hex/UUID-shaped identifier is not flagged.
    private static func isHighEntropyLiteral(_ value: String) -> Bool {
        guard value.count >= minimumHighEntropyLength, !value.contains(where: \.isWhitespace) else { return false }
        guard value.contains(where: \.isNumber), value.contains(where: \.isLetter) else { return false }
        return shannonEntropyPerCharacter(value) > highEntropyThreshold
    }

    private static func shannonEntropyPerCharacter(_ value: String) -> Double {
        var frequency: [Character: Int] = [:]
        for character in value {
            frequency[character, default: 0] += 1
        }
        let length = Double(value.count)
        return frequency.values.reduce(0.0) { total, count in
            let probability = Double(count) / length
            return total - probability * log2(probability)
        }
    }
}
