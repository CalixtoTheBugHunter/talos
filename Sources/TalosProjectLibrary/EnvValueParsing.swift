import Foundation
import TalosCore

/// What makes a raw `env` string one of `EnvValue`'s two cases — shared by
/// every parser that reads a `keychain:<name>` reference or a literal, so
/// "same rule as `agents.yaml`" is one implementation rather than two that
/// can drift apart.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#secret-references-never-secrets
enum EnvValueParsing {
    /// The prefix a raw `env` value must carry to be a Keychain reference
    /// rather than a literal.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
    static let keychainPrefix = "keychain:"

    /// What a raw `env` string resolved to.
    enum Classification: Equatable {
        case secretReference(name: String)
        case emptyKeychainReference
        case literalSecret(reason: String)
        case literal(String)
    }

    /// Classifies `value` found under `key`. Never includes `value` itself
    /// in a `.literalSecret` reason — the message that reports a pasted
    /// secret must not echo it back.
    static func classify(key: String, value: String) -> Classification {
        if value.hasPrefix(keychainPrefix) {
            let name = String(value.dropFirst(keychainPrefix.count))
            return name.isEmpty ? .emptyKeychainReference : .secretReference(name: name)
        }
        if let reason = literalSecretReason(key: key, value: value) {
            return .literalSecret(reason: reason)
        }
        return .literal(value)
    }

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
    /// instead, or `nil` when the literal is ordinary configuration.
    private static func literalSecretReason(key: String, value: String) -> String? {
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
