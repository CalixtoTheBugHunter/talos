import Foundation

/// What resolving a role against the user's configuration and the installed
/// apps produced.
public enum ExternalAppResolution: Equatable, Sendable {
    case resolved(ExternalAppCandidate)
    case missing
}

/// Resolves an ``ExternalAppRole`` to the app Talos should hand off to —
/// "sensible detection of installed apps", plus a user's explicit choice
/// where one exists.
///
/// A configured app that is no longer installed resolves to ``missing``
/// rather than silently falling back to a different installed candidate: a
/// user who chose iTerm and later removed it is told iTerm is gone, not
/// handed a Terminal window they never asked for.
public struct ExternalAppResolver: Sendable {
    private let isInstalled: @Sendable (String) -> Bool

    public init(isInstalled: @escaping @Sendable (String) -> Bool) {
        self.isInstalled = isInstalled
    }

    public func resolve(
        role: ExternalAppRole,
        configured: ExternalAppCandidate?,
        candidates: [ExternalAppCandidate] = []
    ) -> ExternalAppResolution {
        if let configured {
            return isInstalled(configured.bundleIdentifier) ? .resolved(configured) : .missing
        }

        let candidates = candidates.isEmpty ? ExternalAppCandidate.candidates(for: role) : candidates
        guard let firstInstalled = candidates.first(where: { isInstalled($0.bundleIdentifier) }) else {
            return .missing
        }
        return .resolved(firstInstalled)
    }
}
