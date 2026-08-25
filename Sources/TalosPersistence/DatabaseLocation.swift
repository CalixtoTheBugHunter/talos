import Foundation

/// The on-disk location of the local SQLite database.
///
/// Keyed off the bundle identifier rather than the display name, and
/// permanent from the first shipped build: it is a user-visible support
/// path, and moving it later would orphan a user's sessions, token
/// records, memories, and approvals rather than migrate them.
public enum DatabaseLocation {
    /// The bundle identifier for everything Talos owns on disk.
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
