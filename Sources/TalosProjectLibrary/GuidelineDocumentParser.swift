import Foundation
import Yams

/// Parses one `.talos/guidelines/*.md` file against ``GuidelineDocument``.
/// The four declared elements live in a `---`-delimited YAML front matter
/// block that must open the file — the body below it is free-form,
/// human-only documentation this parser never requires and never discards
/// (see ``GuidelineDocument/rawText``). All `Yams` usage is contained to
/// this one file, the same discipline `ConnectorsManifestParser` and
/// `BoardManifestParser` use — the rest of Talos sees only
/// ``GuidelineDocument``.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#editable-talos-guidelines
public enum GuidelineDocumentParser {
    private static let delimiter = "---"
    private static let purposeKey = "purpose"
    private static let contextKey = "context"
    private static let tokenCeilingKey = "tokenCeiling"
    private static let outputExpectationsKey = "outputExpectations"

    /// Parses `contents` as one `.talos/guidelines/<subFunction>.md` file.
    /// `file` is only used to label a thrown ``GuidelineDocumentError`` —
    /// this function does no filesystem access of its own.
    public static func parse(contents: String, subFunction: SubFunction, file: String) throws -> GuidelineDocument {
        let (yaml, lineOffset) = try frontMatter(of: contents, file: file)
        let mapping = try rootMapping(of: yaml, lineOffset: lineOffset, file: file)

        return try GuidelineDocument(
            subFunction: subFunction,
            purpose: parsePurpose(mapping: mapping, lineOffset: lineOffset, file: file),
            context: parseContext(mapping: mapping, lineOffset: lineOffset, file: file),
            tokenCeiling: parseTokenCeiling(mapping: mapping, lineOffset: lineOffset, file: file),
            outputExpectations: parseOutputExpectations(mapping: mapping, lineOffset: lineOffset, file: file),
            rawText: contents
        )
    }

    // MARK: - Locating the front matter block

    /// Splits `contents` on its opening and closing `---` lines and returns
    /// the YAML between them, plus the line the block's content starts at in
    /// `contents` — added to every mark Yams reports against the extracted
    /// substring, so a thrown error names a line in the original file rather
    /// than in the excerpt.
    private static func frontMatter(of contents: String, file: String) throws -> (yaml: String, lineOffset: Int) {
        let lines = contents.components(separatedBy: "\n")
        guard let firstLine = lines.first, firstLine.trimmingCharacters(in: .whitespaces) == delimiter else {
            throw GuidelineDocumentError(
                file: file,
                line: nil,
                fix: "The file must open with a '\(delimiter)' line starting a YAML front matter block " +
                    "that declares '\(purposeKey)', '\(contextKey)', '\(tokenCeilingKey)', and " +
                    "'\(outputExpectationsKey)'."
            )
        }
        guard let closingOffset = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == delimiter
        }) else {
            throw GuidelineDocumentError(
                file: file,
                line: nil,
                fix: "The YAML front matter opened by the first '\(delimiter)' line never closes — add a " +
                    "second '\(delimiter)' line after the declared fields."
            )
        }
        let yamlLines = lines[1 ..< closingOffset]
        return (yamlLines.joined(separator: "\n"), 1)
    }

    private static func rootMapping(of yaml: String, lineOffset: Int, file: String) throws -> Node.Mapping {
        let root: Node
        do {
            guard let node = try Yams.compose(yaml: yaml) else {
                throw GuidelineDocumentError(
                    file: file,
                    line: nil,
                    fix: "Add '\(purposeKey)', '\(contextKey)', '\(tokenCeilingKey)', and " +
                        "'\(outputExpectationsKey)' inside the front matter block — it is currently empty."
                )
            }
            root = node
        } catch let error as GuidelineDocumentError {
            throw error
        } catch {
            throw GuidelineDocumentError(
                file: file, line: absoluteLine(of: error, offset: lineOffset), fix: "Fix the YAML syntax: \(error)"
            )
        }

        guard let mapping = root.mapping else {
            throw GuidelineDocumentError(
                file: file,
                line: root.mark.map { $0.line + lineOffset },
                fix: "The YAML front matter must be a mapping, not a scalar or a sequence."
            )
        }
        return mapping
    }

    // MARK: - Parsing, one field at a time

    private static func parsePurpose(mapping: Node.Mapping, lineOffset: Int, file: String) throws -> String {
        guard let node = mapping[purposeKey], let purpose = node.string, !purpose.isEmpty else {
            throw GuidelineDocumentError(
                file: file,
                line: mapping.mark.map { $0.line + lineOffset },
                fix: "Add a non-empty '\(purposeKey)' string to the front matter."
            )
        }
        return purpose
    }

    private static func parseContext(mapping: Node.Mapping, lineOffset: Int, file: String) throws -> [String] {
        guard let node = mapping[contextKey] else {
            throw GuidelineDocumentError(
                file: file,
                line: mapping.mark.map { $0.line + lineOffset },
                fix: "Add a '\(contextKey)' YAML sequence to the front matter — an empty sequence ('[]') " +
                    "if this guideline wants no additional context assembled."
            )
        }
        guard let sequence = node.sequence else {
            throw GuidelineDocumentError(
                file: file,
                line: node.mark.map { $0.line + lineOffset },
                fix: "'\(contextKey)' must be a YAML sequence of strings."
            )
        }
        return try sequence.map { element in
            guard let value = element.string, !value.isEmpty else {
                throw GuidelineDocumentError(
                    file: file,
                    line: element.mark.map { $0.line + lineOffset },
                    fix: "Every '\(contextKey)' entry must be a non-empty string."
                )
            }
            return value
        }
    }

    private static func parseTokenCeiling(mapping: Node.Mapping, lineOffset: Int, file: String) throws -> Int {
        guard let node = mapping[tokenCeilingKey] else {
            throw GuidelineDocumentError(
                file: file,
                line: mapping.mark.map { $0.line + lineOffset },
                fix: "Add a '\(tokenCeilingKey)' integer greater than zero — the token ceiling is not " +
                    "decoration, it is how the < 5% token overhead budget is enforced per sub-function."
            )
        }
        guard let ceiling = node.int, ceiling > 0 else {
            throw GuidelineDocumentError(
                file: file,
                line: node.mark.map { $0.line + lineOffset },
                fix: "'\(tokenCeilingKey)' must be a whole number greater than zero."
            )
        }
        return ceiling
    }

    private static func parseOutputExpectations(
        mapping: Node.Mapping,
        lineOffset: Int,
        file: String
    ) throws -> String {
        guard let node = mapping[outputExpectationsKey], let value = node.string, !value.isEmpty else {
            throw GuidelineDocumentError(
                file: file,
                line: mapping.mark.map { $0.line + lineOffset },
                fix: "Add a non-empty '\(outputExpectationsKey)' string to the front matter."
            )
        }
        return value
    }

    /// The line a composer/parser/scanner `YamlError` points at, offset back
    /// into the original file's line numbering.
    private static func absoluteLine(of error: Error, offset: Int) -> Int? {
        guard let yamlError = error as? YamlError else { return nil }
        switch yamlError {
        case let .scanner(_, _, mark, _), let .parser(_, _, mark, _), let .composer(_, _, mark, _):
            return mark.line + offset
        default:
            return nil
        }
    }
}
