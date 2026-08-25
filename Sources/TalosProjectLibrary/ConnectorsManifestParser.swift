import Foundation
import Yams

/// Parses `.talos/connectors.yaml` against ``ConnectorsManifest``. All
/// `Yams` usage is contained to this one file, the same discipline
/// `AgentsManifestParser` and `SpecManifestParser` use — the rest of Talos
/// sees only ``ConnectorsManifest``.
public enum ConnectorsManifestParser {
    private static let connectorsKey = "connectors"
    private static let kindKey = "kind"
    private static let targetKey = "target"
    private static let reachedViaKey = "reachedVia"
    private static let envKey = "env"

    /// Parses `contents` as `.talos/connectors.yaml`. `file` is only used
    /// to label a thrown ``ConnectorsManifestError`` — this function does
    /// no filesystem access of its own.
    public static func parse(contents: String, file: String) throws -> ConnectorsManifest {
        let mapping = try rootMapping(of: contents, file: file)
        return try ConnectorsManifest(connectors: parseConnectors(mapping: mapping, file: file))
    }

    // MARK: - Parsing, one field at a time

    /// Composes `contents` and returns its top-level mapping, or throws a
    /// ``ConnectorsManifestError`` naming the line a syntax error or a
    /// non-mapping root was found at.
    private static func rootMapping(of contents: String, file: String) throws -> Node.Mapping {
        let root: Node
        do {
            guard let node = try Yams.compose(yaml: contents) else {
                return [:]
            }
            root = node
        } catch {
            throw ConnectorsManifestError(
                file: file, line: sourceLine(of: error), fix: "Fix the YAML syntax: \(error)"
            )
        }

        guard let mapping = root.mapping else {
            throw ConnectorsManifestError(
                file: file,
                line: root.mark?.line,
                fix: "The top level of '\(file)' must be a YAML mapping, not a scalar or a sequence."
            )
        }
        return mapping
    }

    private static func parseConnectors(mapping: Node.Mapping, file: String) throws -> [ConnectorDeclaration] {
        guard let connectorsNode = mapping[connectorsKey] else { return [] }
        guard let connectorsMapping = connectorsNode.mapping else {
            throw ConnectorsManifestError(
                file: file,
                line: connectorsNode.mark?.line,
                fix: "'\(connectorsKey)' must be a YAML mapping, keyed by connector name."
            )
        }

        return try connectorsMapping.map { key, value in
            guard let name = key.string, !name.isEmpty else {
                throw ConnectorsManifestError(
                    file: file,
                    line: key.mark?.line,
                    fix: "Every key under '\(connectorsKey)' must be a non-empty string naming a connector."
                )
            }
            return try parseConnector(name: name, node: value, file: file)
        }
    }

    private static func parseConnector(name: String, node: Node, file: String) throws -> ConnectorDeclaration {
        guard let connectorMapping = node.mapping else {
            throw ConnectorsManifestError(
                file: file,
                line: node.mark?.line,
                fix: "'\(connectorsKey).\(name)' must be a YAML mapping with '\(kindKey)', '\(targetKey)', " +
                    "and '\(reachedViaKey)' keys."
            )
        }

        return try ConnectorDeclaration(
            name: name,
            kind: parseKind(connectorName: name, mapping: connectorMapping, file: file),
            target: parseTarget(connectorName: name, mapping: connectorMapping, file: file),
            reachedVia: parseReachedVia(connectorName: name, mapping: connectorMapping, file: file),
            env: parseEnv(connectorName: name, mapping: connectorMapping, file: file)
        )
    }

    private static func parseKind(connectorName: String, mapping: Node.Mapping, file: String) throws -> ConnectorKind {
        guard let kindNode = mapping[kindKey], let rawValue = kindNode.string else {
            throw ConnectorsManifestError(
                file: file,
                line: mapping.mark?.line,
                fix: "'\(connectorsKey).\(connectorName)' is missing a required '\(kindKey)' string."
            )
        }
        guard let kind = ConnectorKind(rawValue: rawValue) else {
            let registered = ConnectorKind.allCases.map(\.rawValue).joined(separator: ", ")
            throw ConnectorsManifestError(
                file: file,
                line: kindNode.mark?.line,
                fix: "'\(rawValue)' is not a registered connector kind. Use one of: \(registered)."
            )
        }
        return kind
    }

    private static func parseTarget(connectorName: String, mapping: Node.Mapping, file: String) throws -> String {
        guard let targetNode = mapping[targetKey], let target = targetNode.string, !target.isEmpty else {
            throw ConnectorsManifestError(
                file: file,
                line: mapping.mark?.line,
                fix: "'\(connectorsKey).\(connectorName)' is missing a required non-empty '\(targetKey)' string."
            )
        }
        return target
    }

    private static func parseReachedVia(
        connectorName: String,
        mapping: Node.Mapping,
        file: String
    ) throws -> ConnectorAccessMethod {
        guard let reachedViaNode = mapping[reachedViaKey], let rawValue = reachedViaNode.string else {
            throw ConnectorsManifestError(
                file: file,
                line: mapping.mark?.line,
                fix: "'\(connectorsKey).\(connectorName)' is missing a required '\(reachedViaKey)' string. " +
                    "Use '\(ConnectorAccessMethod.mcp.rawValue)' or '\(ConnectorAccessMethod.cli.rawValue)'."
            )
        }
        guard let reachedVia = ConnectorAccessMethod(rawValue: rawValue) else {
            throw ConnectorsManifestError(
                file: file,
                line: reachedViaNode.mark?.line,
                fix: "'\(rawValue)' is not a recognized '\(reachedViaKey)'. Use " +
                    "'\(ConnectorAccessMethod.mcp.rawValue)' or '\(ConnectorAccessMethod.cli.rawValue)'."
            )
        }
        return reachedVia
    }

    private static func parseEnv(
        connectorName: String,
        mapping: Node.Mapping,
        file: String
    ) throws -> [String: EnvValue] {
        guard let envNode = mapping[envKey] else { return [:] }
        guard let envMapping = envNode.mapping else {
            throw ConnectorsManifestError(
                file: file,
                line: envNode.mark?.line,
                fix: "'\(connectorsKey).\(connectorName).\(envKey)' must be a YAML mapping."
            )
        }

        let path = "\(connectorsKey).\(connectorName)"
        var env: [String: EnvValue] = [:]
        for (keyNode, valueNode) in envMapping {
            guard let key = keyNode.string, !key.isEmpty else {
                throw ConnectorsManifestError(
                    file: file,
                    line: keyNode.mark?.line,
                    fix: "Every key under '\(path).\(envKey)' must be a non-empty string."
                )
            }
            guard let value = valueNode.string else {
                throw ConnectorsManifestError(
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
            throw ConnectorsManifestError(
                file: file,
                line: line,
                fix: "'\(path).\(key)' has an empty Keychain reference — use " +
                    "'\(EnvValueParsing.keychainPrefix)<name>'."
            )
        case let .literalSecret(reason):
            throw ConnectorsManifestError(
                file: file,
                line: line,
                fix: "'\(path).\(key)' \(reason) — use a Keychain reference " +
                    "'\(EnvValueParsing.keychainPrefix)<name>' instead of a literal value."
            )
        case let .literal(literal):
            return .literal(literal)
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
