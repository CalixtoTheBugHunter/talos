import Foundation
@testable import TalosCore
import Testing

/// Verifies the logging facade's subsystem and per-module categories, per
/// https://github.com/CalixtoTheBugHunter/talos/issues/39's "A logging
/// facade over OSLog with defined subsystems per module."
@Suite("Log")
struct LogTests {
    /// The identifier is decision 51's, the same one
    /// `DatabaseLocationTests.bundleIdentifierMatchesDecision51` checks for
    /// `TalosPersistence`.
    @Test("The root identifier matches decision 51's bundle identifier")
    func rootIdentifierMatchesDecision51() {
        #expect(Log.rootIdentifier == "com.calixtothebughunter.talos")
    }

    /// Each module gets its own subsystem — not one shared across all of
    /// them — which is what "defined subsystems per module" means literally.
    @Test(
        "Each category's subsystem is the root identifier plus its own module name",
        arguments: Log.Category.allCases
    )
    func categorySubsystemIsNamespacedUnderTheRoot(category: Log.Category) {
        #expect(category.subsystem == "com.calixtothebughunter.talos.\(category.rawValue)")
    }

    @Test("No two categories share a subsystem")
    func subsystemsAreAllDistinct() {
        let subsystems = Log.Category.allCases.map(\.subsystem)
        #expect(Set(subsystems).count == subsystems.count)
    }

    /// Walks up from this test file's location to the repository root — the
    /// directory containing `Package.swift` — mirroring
    /// `ModuleDependencyGraphTests.repositoryRoot`.
    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        fatalError("Could not locate repository root above \(#filePath)")
    }

    /// > Modules are defined with explicit dependencies: `TalosCore`,
    /// > `TalosOrchestration`, `TalosSafeguards`, `TalosProjectLibrary`,
    /// > `TalosAdapters`, `TalosPersistence`, `TalosUI`
    @Test("Every category names exactly one module, and every module has a category")
    func categoriesMatchArchitectureDocModules() throws {
        let docURL = Self.repositoryRoot.appendingPathComponent("ARCHITECTURE.md")
        let text = try String(contentsOf: docURL, encoding: .utf8)

        let pattern = #"(?m)^\| `([A-Za-z]+)` \|"#
        let regex = try Regex(pattern)
        let moduleNames = Set(text.matches(of: regex).compactMap { $0.output[1].substring.map(String.init) })

        let categoryNames = Set(Log.Category.allCases.map(\.rawValue))
        #expect(categoryNames == moduleNames)
    }

    @Test("Every category produces a logger without trapping", arguments: Log.Category.allCases)
    func loggerConstructsForEveryCategory(category: Log.Category) {
        _ = Log.logger(category)
    }
}
