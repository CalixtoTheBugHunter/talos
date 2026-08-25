import Foundation
import OSLog
import Security
import TalosCore

// The single code path that reads or writes a project secret. Everything
// else in Talos sees a `SecretReference`, never a `SecItem*` call.
// https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution#decisions
// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives
// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#irreversible--outward-facing
// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions

/// Which taxonomy action type a `KeychainSecretAccessor` call is, spelled
/// exactly as
/// [the taxonomy](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy)
/// spells `secret.read` and `secret.write`.
public enum SecretAccessKind: String, Equatable, Hashable, Sendable {
    case read = "secret.read"
    case write = "secret.write"
}

/// One attempted secret access, named for whatever authorizes it before
/// ``KeychainSecretAccessor`` touches the Keychain. Never carries the
/// secret's value — only what the access is, on which project, for which
/// name.
public struct SecretAccessAction: Equatable, Hashable, Sendable {
    public let kind: SecretAccessKind
    public let project: ProjectIdentifier
    public let keychainName: String

    public init(kind: SecretAccessKind, project: ProjectIdentifier, keychainName: String) {
        self.kind = kind
        self.project = project
        self.keychainName = keychainName
    }
}

/// What must authorize a ``SecretAccessAction`` before it runs — the seam
/// the Safeguards gate occupies once it exists. `secret.read` and
/// `secret.write` are always irreversible / outward-facing, never
/// allowlistable, so an authorizer speaks for that gate rather than for a
/// tier decision this type makes itself.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#irreversible--outward-facing
public protocol SecretAccessAuthorizing: Sendable {
    func authorize(_ action: SecretAccessAction) throws
}

/// Thrown when a ``SecretAccessAuthorizing`` denies a ``SecretAccessAction``.
/// The underlying Keychain operation never runs when this is thrown.
public struct SecretAccessDenied: Error, Equatable, Sendable {
    public let action: SecretAccessAction
}

/// Thrown by `read` when no value has been written for the reference —
/// never a silent empty string.
public struct MissingSecretError: Error, Equatable, Sendable {
    public let project: ProjectIdentifier
    public let keychainName: String
    public let fix: String

    public init(project: ProjectIdentifier, keychainName: String) {
        self.project = project
        self.keychainName = keychainName
        fix = "No secret named '\(keychainName)' is stored for this project. " +
            "Store it in the macOS Keychain before referencing 'keychain:\(keychainName)'."
    }
}

/// A Keychain operation failed for a reason other than a missing item —
/// wraps the `OSStatus` so a caller can act on it without this type leaking
/// `Security` framework constants further than necessary.
public struct SecretAccessError: Error, Equatable, Sendable {
    public let status: OSStatus
}

/// The only code path in Talos that reads or writes a project secret.
///
/// Every access is namespaced per project — see
/// [decision 71](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions),
/// which supersedes
/// [decision 69](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions) —
/// and authorized before it touches the Keychain, so one project's
/// `keychain:<name>` reference can never resolve to another project's
/// secret and no access reaches the Keychain ungated.
public struct KeychainSecretAccessor: Sendable {
    /// Fixed regardless of project — only the account varies. Matches
    /// decision 69's service half, which decision 71 left unchanged.
    private static let service = "Talos"

    private let authorizer: SecretAccessAuthorizing
    private let logger = Log.logger(.projectLibrary)

    public init(authorizer: SecretAccessAuthorizing) {
        self.authorizer = authorizer
    }

    /// `<ProjectIdentifier>:<name>` — the project-scoped account decision 71
    /// resolves `keychain:<name>` against.
    private static func account(project: ProjectIdentifier, keychainName: String) -> String {
        "\(project.rawValue):\(keychainName)"
    }

    /// Reads the secret `reference` names, scoped to `project`. Throws
    /// ``MissingSecretError`` when nothing is stored — never returns an
    /// empty string.
    public func read(_ reference: SecretReference, project: ProjectIdentifier) throws -> String {
        let action = SecretAccessAction(kind: .read, project: project, keychainName: reference.keychainName)
        try authorize(action)

        let account = Self.account(project: project, keychainName: reference.keychainName)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else {
            throw MissingSecretError(project: project, keychainName: reference.keychainName)
        }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8)
        else {
            throw SecretAccessError(status: status)
        }

        logAccess(action)
        return value
    }

    /// Writes `value` under `reference`, scoped to `project`. Adds a new
    /// Keychain item, or updates one that already exists for this project
    /// and name.
    public func write(_ reference: SecretReference, project: ProjectIdentifier, value: String) throws {
        let action = SecretAccessAction(kind: .write, project: project, keychainName: reference.keychainName)
        try authorize(action)

        let account = Self.account(project: project, keychainName: reference.keychainName)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]
        let data = Data(value.utf8)

        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SecretAccessError(status: addStatus)
            }
        } else {
            guard updateStatus == errSecSuccess else {
                throw SecretAccessError(status: updateStatus)
            }
        }

        logAccess(action)
    }

    /// Deletes the secret `reference` names, scoped to `project`. Present so
    /// a test can clean up what it wrote; not itself part of the read/write
    /// path a manifest's `env` entries exercise.
    public func delete(_ reference: SecretReference, project: ProjectIdentifier) throws {
        let account = Self.account(project: project, keychainName: reference.keychainName)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretAccessError(status: status)
        }
    }

    private func authorize(_ action: SecretAccessAction) throws {
        do {
            try authorizer.authorize(action)
        } catch {
            throw SecretAccessDenied(action: action)
        }
    }

    /// Logs that `action` happened — never the value. Satisfies "reads are
    /// logged as access events without values" for the accessor's own
    /// access event; the append-only, user-visible audit trail every gated
    /// decision writes is a separate, not-yet-built surface.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
    private func logAccess(_ action: SecretAccessAction) {
        let kind = action.kind.rawValue
        let name = action.keychainName
        let project = action.project.rawValue
        logger.info("\(kind, privacy: .public) \(name, privacy: .public) project=\(project, privacy: .public)")
    }
}
