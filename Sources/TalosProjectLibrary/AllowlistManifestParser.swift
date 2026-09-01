import Foundation
import Yams

/// Parses and serializes `.talos/allowlist.yaml` against ``AllowlistManifest``.
/// All `Yams` usage is contained to this one file, the same discipline
/// `ConnectorsManifestParser` and the other `.talos/` parsers use.
public enum AllowlistManifestParser {
    private static let allowlistKey = "allowlist"

    /// Parses `contents` as `.talos/allowlist.yaml`. `file` is only used to
    /// label a thrown ``AllowlistManifestError`` — this function does no
    /// filesystem access of its own.
    ///
    /// A missing `allowlist:` key parses as an empty manifest, the same
    /// default-open-for-absence-not-content reading `ConnectorsManifestParser`
    /// gives a missing `connectors:` key — a project with no file yet has no
    /// allowlisted actions, which is exactly deny-by-default.
    public static func parse(contents: String, file: String) throws -> AllowlistManifest {
        let mapping = try rootMapping(of: contents, file: file)
        guard let entriesNode = mapping[allowlistKey] else {
            return AllowlistManifest()
        }
        guard let sequence = entriesNode.sequence else {
            throw AllowlistManifestError(
                file: file,
                line: entriesNode.mark?.line,
                fix: "'\(allowlistKey)' must be a YAML sequence of action-type name strings."
            )
        }

        let entries = try sequence.map { node -> String in
            guard let entry = node.string, !entry.isEmpty else {
                throw AllowlistManifestError(
                    file: file,
                    line: node.mark?.line,
                    fix: "Every entry under '\(allowlistKey)' must be a non-empty string naming an action type."
                )
            }
            return entry
        }
        return AllowlistManifest(entries: entries)
    }

    /// Renders `manifest` back to the same shape ``parse`` reads, so a store
    /// can round-trip a change to disk without hand-building YAML text.
    public static func serialize(_ manifest: AllowlistManifest) -> String {
        guard !manifest.entries.isEmpty else {
            return "\(allowlistKey): []\n"
        }
        let lines = manifest.entries.map { "  - \($0)" }.joined(separator: "\n")
        return "\(allowlistKey):\n\(lines)\n"
    }

    // MARK: - Parsing

    private static func rootMapping(of contents: String, file: String) throws -> Node.Mapping {
        let root: Node
        do {
            guard let node = try Yams.compose(yaml: contents) else {
                return [:]
            }
            root = node
        } catch {
            throw AllowlistManifestError(
                file: file, line: sourceLine(of: error), fix: "Fix the YAML syntax: \(error)"
            )
        }

        guard let mapping = root.mapping else {
            throw AllowlistManifestError(
                file: file,
                line: root.mark?.line,
                fix: "The top level of '\(file)' must be a YAML mapping, not a scalar or a sequence."
            )
        }
        return mapping
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
