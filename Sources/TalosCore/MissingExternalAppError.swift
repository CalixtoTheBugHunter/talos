import Foundation

/// Thrown when a role resolves to ``ExternalAppResolution/missing`` — "a
/// missing configured app produces an actionable error, not a silent
/// no-op." Never thrown silently: `fix` is what a caller shows the user.
public struct MissingExternalAppError: Error, Equatable, Sendable {
    public let role: ExternalAppRole
    public let configured: ExternalAppCandidate?
    public let fix: String

    public init(role: ExternalAppRole, configured: ExternalAppCandidate?) {
        self.role = role
        self.configured = configured
        if let configured {
            fix = "\(configured.name) is configured for \(role.rawValue) but is not installed. " +
                "Install it, or choose a different app."
        } else {
            let names = ExternalAppCandidate.candidates(for: role).map(\.name).joined(separator: ", ")
            fix = "No \(role.rawValue) app is installed among the detected candidates (\(names)). " +
                "Install one, or choose a different app."
        }
    }
}
