import Foundation
import Yams

/// Parses `.talos/agents.yaml` against ``AgentsManifest``. All `Yams` usage
/// is contained to this one file, the same discipline `ProjectManifestParser`
/// uses for `project.yaml` — the rest of Talos sees only ``AgentsManifest``.
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
                        "'\(EnvValueParsing.keychainPrefix)<name>' reference."
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
        switch EnvValueParsing.classify(key: key, value: value) {
        case let .secretReference(name):
            return .secret(SecretReference(keychainName: name))
        case .emptyKeychainReference:
            throw AgentsManifestError(
                file: file,
                line: line,
                fix: "'\(path).\(key)' has an empty Keychain reference — use " +
                    "'\(EnvValueParsing.keychainPrefix)<name>'."
            )
        case let .literalSecret(reason):
            throw AgentsManifestError(
                file: file,
                line: line,
                fix: "'\(path).\(key)' \(reason) — use a Keychain reference " +
                    "'\(EnvValueParsing.keychainPrefix)<name>' instead of a literal value."
            )
        case let .literal(literal):
            return .literal(literal)
        }
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
