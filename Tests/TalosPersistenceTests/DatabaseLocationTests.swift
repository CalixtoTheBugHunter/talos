import Foundation
@testable import TalosPersistence
import Testing

@Suite("Database location")
struct DatabaseLocationTests {
    @Test("The default database URL is under Application Support, keyed by the bundle identifier")
    func defaultURLIsUnderApplicationSupport() {
        let appSupport = URL(fileURLWithPath: "/Users/example/Library/Application Support", isDirectory: true)
        let url = DatabaseLocation.defaultDatabaseURL(applicationSupportDirectory: appSupport)

        #expect(url.deletingLastPathComponent().lastPathComponent == "com.calixtothebughunter.talos")
        #expect(url.lastPathComponent == "talos.sqlite")
        #expect(url.path == "/Users/example/Library/Application Support/com.calixtothebughunter.talos/talos.sqlite")
    }

    /// Not a second identifier invented separately from `Log.rootIdentifier`.
    @Test("The bundle identifier matches decision 51")
    func bundleIdentifierMatchesDecision51() {
        #expect(DatabaseLocation.bundleIdentifier == "com.calixtothebughunter.talos")
    }
}
