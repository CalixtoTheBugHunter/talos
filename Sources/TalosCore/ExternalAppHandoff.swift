import Foundation

/// "Talos opens your terminal app... at the project path" and "Talos opens
/// the affected files in your preferred IDE" — the two commands behind
/// those lines.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-you-use-instead
public struct ExternalAppHandoff: Sendable {
    private let resolver: ExternalAppResolver
    private let preferences: ExternalAppPreferenceStoring
    private let launcher: ExternalAppLauncher

    public init(
        resolver: ExternalAppResolver,
        preferences: ExternalAppPreferenceStoring,
        launcher: ExternalAppLauncher
    ) {
        self.resolver = resolver
        self.preferences = preferences
        self.launcher = launcher
    }

    /// Opens the user's configured terminal app at `projectPath`.
    public func openTerminal(atProjectPath projectPath: URL) throws {
        try open(role: .terminal, paths: [projectPath])
    }

    /// Opens `files` in the user's configured IDE. Never prompts: this is a
    /// Talos-invoked command, not a gated agent action.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#read-tier
    public func openInIDE(files: [URL]) throws {
        try open(role: .ide, paths: files)
    }

    private func open(role: ExternalAppRole, paths: [URL]) throws {
        let configured = preferences.configuredApp(for: role)
        switch resolver.resolve(role: role, configured: configured) {
        case let .resolved(app):
            try launcher.open(paths: paths, withAppBundleIdentifier: app.bundleIdentifier)
        case .missing:
            throw MissingExternalAppError(role: role, configured: configured)
        }
    }
}
