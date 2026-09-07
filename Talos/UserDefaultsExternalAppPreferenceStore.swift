import Foundation
import TalosCore

/// `UserDefaults`-backed storage for the user's chosen terminal/IDE — a
/// personal machine preference, so `UserDefaults` rather than the
/// project-versioned `.talos/` is where it belongs.
///
/// `@unchecked Sendable` because `UserDefaults` predates `Sendable` and is
/// not annotated, though Apple documents its API as thread-safe.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives
struct UserDefaultsExternalAppPreferenceStore: ExternalAppPreferenceStoring, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func configuredApp(for role: ExternalAppRole) -> ExternalAppCandidate? {
        guard let bundleIdentifier = defaults.string(forKey: bundleIdentifierKey(for: role)) else { return nil }
        let name = defaults.string(forKey: nameKey(for: role)) ?? bundleIdentifier
        return ExternalAppCandidate(name: name, bundleIdentifier: bundleIdentifier)
    }

    func setConfiguredApp(_ app: ExternalAppCandidate?, for role: ExternalAppRole) {
        guard let app else {
            defaults.removeObject(forKey: bundleIdentifierKey(for: role))
            defaults.removeObject(forKey: nameKey(for: role))
            return
        }
        defaults.set(app.bundleIdentifier, forKey: bundleIdentifierKey(for: role))
        defaults.set(app.name, forKey: nameKey(for: role))
    }

    private func bundleIdentifierKey(for role: ExternalAppRole) -> String {
        "com.talos.externalApp.\(role.rawValue).bundleIdentifier"
    }

    private func nameKey(for role: ExternalAppRole) -> String {
        "com.talos.externalApp.\(role.rawValue).name"
    }
}
