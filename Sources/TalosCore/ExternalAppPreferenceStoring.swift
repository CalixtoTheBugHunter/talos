import Foundation

/// Where a user's explicit terminal/IDE choice is stored — "Both are
/// configurable". A personal machine preference, not project config: it
/// never belongs under the project's versioned `.talos/`.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives
public protocol ExternalAppPreferenceStoring: Sendable {
    func configuredApp(for role: ExternalAppRole) -> ExternalAppCandidate?
    func setConfiguredApp(_ app: ExternalAppCandidate?, for role: ExternalAppRole)
}
