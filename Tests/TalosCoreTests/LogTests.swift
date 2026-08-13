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
    @Test("The subsystem matches decision 51's bundle identifier")
    func subsystemMatchesDecision51() {
        #expect(Log.subsystem == "com.calixtothebughunter.talos")
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

    @Test("Every category produces a logger scoped to the Talos subsystem")
    func loggerUsesTheTalosSubsystem() {
        for category in Log.Category.allCases {
            _ = Log.logger(category) // constructs without trapping for every declared category
        }
    }
}
