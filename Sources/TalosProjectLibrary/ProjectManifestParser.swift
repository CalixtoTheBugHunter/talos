import Foundation
import Yams

/// Parses and serializes `.talos/project.yaml` against ``ProjectManifest``.
///
/// All `Yams` usage is contained to this one file — the rest of Talos sees
/// only ``ProjectManifest`` and ``TalosYAMLValue``, neither of which imports
/// `Yams`. This is what keeps the new dependency's surface small per
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#talos-is-not-complicated.
///
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives
/// https://github.com/CalixtoTheBugHunter/talos/issues/42
public enum ProjectManifestParser {
    private static let idKey = "id"
    private static let agentsKey = "agents"
    private static let subFunctionsKey = "subFunctions"

    /// Parses `contents` as `.talos/project.yaml`. `file` is only used to
    /// label a thrown ``ProjectManifestError`` — this function does no
    /// filesystem access of its own.
    public static func parse(contents: String, file: String) throws -> ProjectManifest {
        let mapping = try rootMapping(of: contents, file: file)
        return try ProjectManifest(
            id: parseIdentifier(mapping: mapping, file: file),
            configuredAgents: parseConfiguredAgents(mapping: mapping, file: file),
            subFunctions: parseSubFunctions(mapping: mapping, file: file),
            unknownTopLevelKeys: parseUnknownTopLevelKeys(mapping: mapping)
        )
    }

    /// Serializes `manifest` back to YAML, re-emitting `unknownTopLevelKeys`
    /// unchanged so a key this version of Talos does not recognize survives
    /// a rewrite rather than being discarded.
    public static func serialize(_ manifest: ProjectManifest) throws -> String {
        var pairs: [(Node, Node)] = [
            (Node(idKey), Node(manifest.id.rawValue)),
            (Node(agentsKey), Node(manifest.configuredAgents.map { Node($0) }))
        ]

        let subFunctionPairs: [(Node, Node)] = SubFunction.allCases.compactMap { subFunction in
            guard let enabled = manifest.subFunctions[subFunction] else { return nil }
            return (Node(subFunction.rawValue), Node(enabled ? "true" : "false"))
        }
        if !subFunctionPairs.isEmpty {
            pairs.append((Node(subFunctionsKey), Node(subFunctionPairs)))
        }

        for (name, value) in manifest.unknownTopLevelKeys.sorted(by: { $0.key < $1.key }) {
            pairs.append((Node(name), node(from: value)))
        }

        return try Yams.serialize(node: Node(pairs))
    }

    // MARK: - Parsing, one field at a time

    /// Composes `contents` and returns its top-level mapping, or throws a
    /// ``ProjectManifestError`` naming the line a syntax error or a
    /// non-mapping root was found at.
    private static func rootMapping(of contents: String, file: String) throws -> Node.Mapping {
        let root: Node
        do {
            guard let node = try Yams.compose(yaml: contents) else {
                throw ProjectManifestError(
                    file: file,
                    line: nil,
                    fix: "Add '\(idKey): <uuid>' — the file has no content to parse."
                )
            }
            root = node
        } catch let error as ProjectManifestError {
            throw error
        } catch {
            throw ProjectManifestError(file: file, line: sourceLine(of: error), fix: "Fix the YAML syntax: \(error)")
        }

        guard let mapping = root.mapping else {
            throw ProjectManifestError(
                file: file,
                line: root.mark?.line,
                fix: "The top level of '\(file)' must be a YAML mapping, not a scalar or a sequence."
            )
        }
        return mapping
    }

    private static func parseIdentifier(mapping: Node.Mapping, file: String) throws -> ProjectIdentifier {
        guard let idNode = mapping[idKey] else {
            throw ProjectManifestError(
                file: file,
                line: mapping.mark?.line,
                fix: "Add a non-empty '\(idKey): <uuid>' — generate one with ProjectIdentifier.generate() " +
                    "rather than deriving it from the project's path or repo name."
            )
        }
        guard let idString = idNode.string, !idString.isEmpty else {
            throw ProjectManifestError(
                file: file,
                line: idNode.mark?.line,
                fix: "'\(idKey)' must be a non-empty string."
            )
        }
        return ProjectIdentifier(rawValue: idString)
    }

    private static func parseConfiguredAgents(mapping: Node.Mapping, file: String) throws -> [String] {
        guard let agentsNode = mapping[agentsKey] else { return [] }
        guard let sequence = agentsNode.sequence else {
            throw ProjectManifestError(
                file: file,
                line: agentsNode.mark?.line,
                fix: "'\(agentsKey)' must be a YAML sequence of agent name strings."
            )
        }
        return try sequence.map { element in
            guard let name = element.string else {
                throw ProjectManifestError(
                    file: file,
                    line: element.mark?.line,
                    fix: "Every '\(agentsKey)' entry must be a string naming an agent " +
                        "declared in agents.yaml."
                )
            }
            return name
        }
    }

    private static func parseSubFunctions(mapping: Node.Mapping, file: String) throws -> [SubFunction: Bool] {
        guard let subFunctionsNode = mapping[subFunctionsKey] else { return [:] }
        guard let subFunctionsMapping = subFunctionsNode.mapping else {
            throw ProjectManifestError(
                file: file,
                line: subFunctionsNode.mark?.line,
                fix: "'\(subFunctionsKey)' must be a YAML mapping of sub-function name to true/false."
            )
        }

        var subFunctions: [SubFunction: Bool] = [:]
        for (key, value) in subFunctionsMapping {
            guard let name = key.string else {
                throw ProjectManifestError(
                    file: file,
                    line: key.mark?.line,
                    fix: "Every key under '\(subFunctionsKey)' must be a string."
                )
            }
            guard let subFunction = SubFunction(rawValue: name) else {
                let recognized = SubFunction.allCases.map(\.rawValue).joined(separator: ", ")
                throw ProjectManifestError(
                    file: file,
                    line: key.mark?.line,
                    fix: "'\(name)' is not a recognized sub-function. Use one of: \(recognized)."
                )
            }
            guard let enabled = value.bool else {
                throw ProjectManifestError(
                    file: file,
                    line: value.mark?.line,
                    fix: "'\(subFunctionsKey).\(name)' must be 'true' or 'false'."
                )
            }
            subFunctions[subFunction] = enabled
        }
        return subFunctions
    }

    private static func parseUnknownTopLevelKeys(mapping: Node.Mapping) -> [String: TalosYAMLValue] {
        var unknownTopLevelKeys: [String: TalosYAMLValue] = [:]
        for (key, value) in mapping {
            guard let name = key.string, name != idKey, name != agentsKey, name != subFunctionsKey else {
                continue
            }
            unknownTopLevelKeys[name] = talosValue(from: value)
        }
        return unknownTopLevelKeys
    }

    /// The line a composer/parser/scanner `YamlError` points at, when it
    /// carries one — used so a syntax error still names a line per this
    /// issue's validation-error acceptance criterion.
    private static func sourceLine(of error: Error) -> Int? {
        guard let yamlError = error as? YamlError else { return nil }
        switch yamlError {
        case let .scanner(_, _, mark, _), let .parser(_, _, mark, _), let .composer(_, _, mark, _):
            return mark.line
        default:
            return nil
        }
    }

    // MARK: - Unknown-value preservation

    /// Converts an arbitrary parsed `Node` into the Yams-free
    /// ``TalosYAMLValue`` an unrecognized key is preserved as. Order of
    /// checks matters only in that `.string` is the fallback: exactly one of
    /// `.null`/`.bool`/`.int`/`.float` matches a given scalar's resolved tag.
    private static func talosValue(from node: Node) -> TalosYAMLValue {
        if let mapping = node.mapping {
            var map: [String: TalosYAMLValue] = [:]
            for (key, value) in mapping {
                guard let name = key.string else { continue }
                map[name] = talosValue(from: value)
            }
            return .map(map)
        }
        if let sequence = node.sequence {
            return .array(sequence.map(talosValue(from:)))
        }
        if node.null != nil {
            return .null
        }
        if let bool = node.bool {
            return .bool(bool)
        }
        if let int = node.int {
            return .int(int)
        }
        if let double = node.float {
            return .double(double)
        }
        return .string(node.string ?? "")
    }

    /// The inverse of ``talosValue(from:)``, used when re-emitting an
    /// unrecognized key on rewrite. A string is always emitted double-quoted
    /// rather than left to Yams's default plain style: `Yams.Emitter` always
    /// marks a scalar event's tag as implicit regardless of the `Node`'s own
    /// tag (both `plain_implicit` and `quoted_implicit` are hard-coded to
    /// `1`), so tagging the node `.str` alone does not stop a value like
    /// `"true"` or `"null"` from being re-read as a bool or null on the next
    /// parse. Forcing the quoted style is what actually stops it — the exact
    /// silent discard ``ProjectManifest``'s doc comment says unknown keys
    /// must survive.
    private static func node(from value: TalosYAMLValue) -> Node {
        switch value {
        case let .string(string):
            Node(string, Tag(.str), .doubleQuoted)
        case let .bool(bool):
            Node(bool ? "true" : "false")
        case let .int(int):
            Node(String(int))
        case let .double(double):
            Node(String(double))
        case .null:
            Node("null")
        case let .array(array):
            Node(array.map(node(from:)))
        case let .map(map):
            Node(map.sorted(by: { $0.key < $1.key }).map {
                (Node($0.key, Tag(.str), .doubleQuoted), node(from: $0.value))
            })
        }
    }
}
