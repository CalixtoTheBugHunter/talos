import Foundation
@testable import TalosPersistence
import Testing

/// Verifies the database path decision 55 records.
///
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
@Suite("Database location")
struct DatabaseLocationTests {
    /// > `~/Library/Application Support/com.calixtothebughunter.talos/talos.sqlite`,
    /// > keyed off the bundle identifier rather than the display name.
    @Test("The default database URL is under Application Support, keyed by the bundle identifier")
    func defaultURLIsUnderApplicationSupport() {
        let appSupport = URL(fileURLWithPath: "/Users/example/Library/Application Support", isDirectory: true)
        let url = DatabaseLocation.defaultDatabaseURL(applicationSupportDirectory: appSupport)

        #expect(url.deletingLastPathComponent().lastPathComponent == "com.calixtothebughunter.talos")
        #expect(url.lastPathComponent == "talos.sqlite")
        #expect(url.path == "/Users/example/Library/Application Support/com.calixtothebughunter.talos/talos.sqlite")
    }

    /// The identifier is decision 51's, not a second one invented here.
    @Test("The bundle identifier matches decision 51")
    func bundleIdentifierMatchesDecision51() {
        #expect(DatabaseLocation.bundleIdentifier == "com.calixtothebughunter.talos")
    }
}
