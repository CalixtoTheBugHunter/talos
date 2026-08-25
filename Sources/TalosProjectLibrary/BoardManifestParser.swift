import Foundation
import Yams

/// Parses `.talos/board.yaml` against ``BoardManifest``. All `Yams` usage is
/// contained to this one file, the same discipline `ConnectorsManifestParser`
/// and `SpecManifestParser` use — the rest of Talos sees only
/// ``BoardManifest``.
public enum BoardManifestParser {
    private static let boardKey = "board"
    private static let providerKey = "provider"
    private static let columnsKey = "columns"

    /// Parses `contents` as `.talos/board.yaml`. `file` is only used to
    /// label a thrown ``BoardManifestError`` — this function does no
    /// filesystem access of its own.
    public static func parse(contents: String, file: String) throws -> BoardManifest {
        let mapping = try rootMapping(of: contents, file: file)
        let boardMapping = try boardMapping(mapping: mapping, file: file)
        return try BoardManifest(
            provider: parseProvider(mapping: boardMapping, file: file),
            columns: parseColumns(mapping: boardMapping, file: file)
        )
    }

    // MARK: - Parsing, one field at a time

    /// Composes `contents` and returns its top-level mapping, or throws a
    /// ``BoardManifestError`` naming the line a syntax error or a
    /// non-mapping root was found at.
    private static func rootMapping(of contents: String, file: String) throws -> Node.Mapping {
        let root: Node
        do {
            guard let node = try Yams.compose(yaml: contents) else {
                throw BoardManifestError(
                    file: file,
                    line: nil,
                    fix: "Add a '\(boardKey)' mapping with a '\(providerKey)' — the file has no " +
                        "content to parse, and a missing '\(boardKey)' key is not a declared configuration."
                )
            }
            root = node
        } catch let error as BoardManifestError {
            throw error
        } catch {
            throw BoardManifestError(file: file, line: sourceLine(of: error), fix: "Fix the YAML syntax: \(error)")
        }

        guard let mapping = root.mapping else {
            throw BoardManifestError(
                file: file,
                line: root.mark?.line,
                fix: "The top level of '\(file)' must be a YAML mapping, not a scalar or a sequence."
            )
        }
        return mapping
    }

    private static func boardMapping(mapping: Node.Mapping, file: String) throws -> Node.Mapping {
        guard let boardNode = mapping[boardKey] else {
            throw BoardManifestError(
                file: file,
                line: mapping.mark?.line,
                fix: "Add a '\(boardKey)' mapping with a '\(providerKey)' — a missing '\(boardKey)' " +
                    "key is not a declared configuration."
            )
        }
        guard let boardMapping = boardNode.mapping else {
            throw BoardManifestError(
                file: file,
                line: boardNode.mark?.line,
                fix: "'\(boardKey)' must be a YAML mapping with a '\(providerKey)' key."
            )
        }
        return boardMapping
    }

    private static func parseProvider(mapping: Node.Mapping, file: String) throws -> BoardProviderKind {
        guard let providerNode = mapping[providerKey], let rawValue = providerNode.string else {
            throw BoardManifestError(
                file: file,
                line: mapping.mark?.line,
                fix: "'\(boardKey)' is missing a required '\(providerKey)' string."
            )
        }
        guard let provider = BoardProviderKind(rawValue: rawValue) else {
            let registered = BoardProviderKind.allCases.map(\.rawValue).joined(separator: ", ")
            throw BoardManifestError(
                file: file,
                line: providerNode.mark?.line,
                fix: "'\(rawValue)' is not a registered board provider. Use one of: \(registered)."
            )
        }
        return provider
    }

    private static func parseColumns(mapping: Node.Mapping, file: String) throws -> [BoardColumnMapping] {
        guard let columnsNode = mapping[columnsKey] else { return [] }
        guard let columnsMapping = columnsNode.mapping else {
            throw BoardManifestError(
                file: file,
                line: columnsNode.mark?.line,
                fix: "'\(boardKey).\(columnsKey)' must be a YAML mapping, keyed by the provider's column name."
            )
        }

        return try columnsMapping.map { key, value in
            guard let column = key.string, !column.isEmpty else {
                throw BoardManifestError(
                    file: file,
                    line: key.mark?.line,
                    fix: "Every key under '\(boardKey).\(columnsKey)' must be a non-empty string naming a column."
                )
            }
            return try BoardColumnMapping(column: column, state: parseState(column: column, node: value, file: file))
        }
    }

    private static func parseState(column: String, node: Node, file: String) throws -> BoardState {
        guard let rawValue = node.string else {
            let registered = BoardState.allCases.map(\.rawValue).joined(separator: ", ")
            throw BoardManifestError(
                file: file,
                line: node.mark?.line,
                fix: "'\(boardKey).\(columnsKey).\(column)' must be a string naming one of the six " +
                    "internal states: \(registered)."
            )
        }
        guard let state = BoardState(rawValue: rawValue) else {
            let registered = BoardState.allCases.map(\.rawValue).joined(separator: ", ")
            throw BoardManifestError(
                file: file,
                line: node.mark?.line,
                fix: "'\(rawValue)' is not one of the six canonical internal states. Use one of: \(registered)."
            )
        }
        return state
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
