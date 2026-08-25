import Foundation
import Yams

/// Parses `.talos/spec.yaml` against ``SpecManifest``.
///
/// All `Yams` usage is contained to this one file, the same discipline
/// `ProjectManifestParser` and `AgentsManifestParser` use — the rest of
/// Talos sees only ``SpecManifest``.
///
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#spec-drive
/// https://github.com/CalixtoTheBugHunter/talos/issues/44
public enum SpecManifestParser {
    private static let specDriveKey = "specDrive"
    private static let statusKey = "status"
    private static let locationsKey = "locations"
    private static let providerKey = "provider"
    private static let urlKey = "url"
    private static let syncRuleKey = "syncRule"

    private static let absentStatus = "absent"
    private static let presentStatus = "present"

    /// Parses `contents` as `.talos/spec.yaml`. `file` is only used to
    /// label a thrown ``SpecManifestError`` — this function does no
    /// filesystem access of its own.
    public static func parse(contents: String, file: String) throws -> SpecManifest {
        let mapping = try rootMapping(of: contents, file: file)
        return try SpecManifest(specDrive: parseSpecDrive(mapping: mapping, file: file))
    }

    // MARK: - Parsing, one field at a time

    /// Composes `contents` and returns its top-level mapping, or throws a
    /// ``SpecManifestError`` naming the line a syntax error or a
    /// non-mapping root was found at.
    private static func rootMapping(of contents: String, file: String) throws -> Node.Mapping {
        let root: Node
        do {
            guard let node = try Yams.compose(yaml: contents) else {
                throw SpecManifestError(
                    file: file,
                    line: nil,
                    fix: "Add '\(specDriveKey): {\(statusKey): \(absentStatus)}' — the file has no " +
                        "content to parse, and a missing key is not the same as a declared absence."
                )
            }
            root = node
        } catch let error as SpecManifestError {
            throw error
        } catch {
            throw SpecManifestError(file: file, line: sourceLine(of: error), fix: "Fix the YAML syntax: \(error)")
        }

        guard let mapping = root.mapping else {
            throw SpecManifestError(
                file: file,
                line: root.mark?.line,
                fix: "The top level of '\(file)' must be a YAML mapping, not a scalar or a sequence."
            )
        }
        return mapping
    }

    private static func parseSpecDrive(mapping: Node.Mapping, file: String) throws -> SpecDrive {
        guard let specDriveNode = mapping[specDriveKey] else {
            throw SpecManifestError(
                file: file,
                line: mapping.mark?.line,
                fix: "Add '\(specDriveKey): {\(statusKey): \(absentStatus)}', or a '\(presentStatus)' block " +
                    "with '\(locationsKey)' — a missing '\(specDriveKey)' key is not a declared absence."
            )
        }
        guard let specDriveMapping = specDriveNode.mapping else {
            throw SpecManifestError(
                file: file,
                line: specDriveNode.mark?.line,
                fix: "'\(specDriveKey)' must be a YAML mapping with a '\(statusKey)' key."
            )
        }

        let status = try parseStatus(mapping: specDriveMapping, file: file)
        switch status {
        case .absent:
            if specDriveMapping[locationsKey] != nil {
                throw SpecManifestError(
                    file: file,
                    line: specDriveMapping.mark?.line,
                    fix: "'\(specDriveKey)' declares '\(statusKey): \(absentStatus)' and '\(locationsKey)' " +
                        "together, which contradicts itself. Remove '\(locationsKey)', or set " +
                        "'\(statusKey): \(presentStatus)'."
                )
            }
            return .absent
        case .present:
            return try .locations(parseLocations(mapping: specDriveMapping, file: file))
        }
    }

    private enum Status {
        case absent
        case present
    }

    private static func parseStatus(mapping: Node.Mapping, file: String) throws -> Status {
        guard let statusNode = mapping[statusKey], let rawValue = statusNode.string else {
            throw SpecManifestError(
                file: file,
                line: mapping.mark?.line,
                fix: "'\(specDriveKey)' is missing a required '\(statusKey)' string. " +
                    "Use '\(absentStatus)' or '\(presentStatus)'."
            )
        }
        switch rawValue {
        case absentStatus:
            return .absent
        case presentStatus:
            return .present
        default:
            throw SpecManifestError(
                file: file,
                line: statusNode.mark?.line,
                fix: "'\(rawValue)' is not a recognized '\(statusKey)'. Use '\(absentStatus)' or '\(presentStatus)'."
            )
        }
    }

    private static func parseLocations(mapping: Node.Mapping, file: String) throws -> [SpecDriveLocation] {
        guard let locationsNode = mapping[locationsKey] else {
            throw SpecManifestError(
                file: file,
                line: mapping.mark?.line,
                fix: "'\(specDriveKey)' declares '\(statusKey): \(presentStatus)' but has no " +
                    "'\(locationsKey)' — add one or more, or set '\(statusKey): \(absentStatus)'."
            )
        }
        guard let sequence = locationsNode.sequence else {
            throw SpecManifestError(
                file: file,
                line: locationsNode.mark?.line,
                fix: "'\(locationsKey)' must be a YAML sequence of Spec Drive location mappings."
            )
        }
        guard !sequence.isEmpty else {
            throw SpecManifestError(
                file: file,
                line: locationsNode.mark?.line,
                fix: "'\(locationsKey)' is empty. Declare one or more locations, or set " +
                    "'\(statusKey): \(absentStatus)' instead of an empty '\(presentStatus)' block."
            )
        }
        return try sequence.map { try parseLocation(node: $0, file: file) }
    }

    private static func parseLocation(node: Node, file: String) throws -> SpecDriveLocation {
        guard let locationMapping = node.mapping else {
            throw SpecManifestError(
                file: file,
                line: node.mark?.line,
                fix: "Every '\(locationsKey)' entry must be a YAML mapping with '\(providerKey)', " +
                    "'\(urlKey)', and '\(syncRuleKey)'."
            )
        }

        return try SpecDriveLocation(
            provider: parseProvider(mapping: locationMapping, file: file),
            url: parseURL(mapping: locationMapping, file: file),
            syncRule: parseSyncRule(mapping: locationMapping, file: file)
        )
    }

    private static func parseProvider(mapping: Node.Mapping, file: String) throws -> SpecDriveProviderKind {
        guard let providerNode = mapping[providerKey], let rawValue = providerNode.string else {
            throw SpecManifestError(
                file: file,
                line: mapping.mark?.line,
                fix: "This '\(locationsKey)' entry is missing a required '\(providerKey)' string."
            )
        }
        guard let provider = SpecDriveProviderKind(rawValue: rawValue) else {
            let registered = SpecDriveProviderKind.allCases.map(\.rawValue).joined(separator: ", ")
            throw SpecManifestError(
                file: file,
                line: providerNode.mark?.line,
                fix: "'\(rawValue)' is not a registered Spec Drive provider. Use one of: \(registered)."
            )
        }
        return provider
    }

    private static func parseURL(mapping: Node.Mapping, file: String) throws -> String {
        guard let urlNode = mapping[urlKey], let rawValue = urlNode.string, !rawValue.isEmpty else {
            throw SpecManifestError(
                file: file,
                line: mapping.mark?.line,
                fix: "This '\(locationsKey)' entry is missing a required non-empty '\(urlKey)' string."
            )
        }
        guard let url = URL(string: rawValue), url.scheme != nil else {
            throw SpecManifestError(
                file: file,
                line: urlNode.mark?.line,
                fix: "'\(urlKey): \(rawValue)' cannot be resolved — it is not a well-formed URL with a scheme."
            )
        }
        return rawValue
    }

    private static func parseSyncRule(mapping: Node.Mapping, file: String) throws -> SpecDriveSyncRule {
        guard let syncRuleNode = mapping[syncRuleKey], let rawValue = syncRuleNode.string else {
            throw SpecManifestError(
                file: file,
                line: mapping.mark?.line,
                fix: "This '\(locationsKey)' entry is missing a required '\(syncRuleKey)' string."
            )
        }
        guard let syncRule = SpecDriveSyncRule(rawValue: rawValue) else {
            throw SpecManifestError(
                file: file,
                line: syncRuleNode.mark?.line,
                fix: "'\(rawValue)' is not a recognized '\(syncRuleKey)'. Use " +
                    "'\(SpecDriveSyncRule.readOnly.rawValue)' or '\(SpecDriveSyncRule.talosMayEdit.rawValue)'."
            )
        }
        return syncRule
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
