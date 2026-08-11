import Foundation

/// The on-disk location of the local SQLite database.
///
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
/// (decision 55) — keyed off the bundle identifier
/// (https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions,
/// decision 51) rather than the display name, and permanent from the first
/// shipped build for the same reason: it is a user-visible support path, and
/// moving it later would orphan a user's sessions, token records, memories,
/// and approvals rather than migrate them.
public enum DatabaseLocation {
    /// The bundle identifier decision 51 fixed for everything Talos owns on
    /// disk.
    public static let bundleIdentifier = "com.calixtothebughunter.talos"

    /// `~/Library/Application Support/com.calixtothebughunter.talos/talos.sqlite`
    public static func defaultDatabaseURL(
        applicationSupportDirectory: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
    ) -> URL {
        applicationSupportDirectory
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("talos.sqlite", isDirectory: false)
    }
}
