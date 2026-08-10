import Foundation
@testable import TalosCore
import Testing

/// Verifies the module graph `Package.swift` declares matches the one
/// `ARCHITECTURE.md` documents.
///
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
/// https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#notes-on-the-harder-criteria
@Suite("Module dependency graph")
struct ModuleDependencyGraphTests {
    /// The seven modules named in
    /// https://github.com/CalixtoTheBugHunter/talos/issues/36.
    static let expectedModuleNames: Set<String> = [
        "TalosCore",
        "TalosOrchestration",
        "TalosSafeguards",
        "TalosProjectLibrary",
        "TalosAdapters",
        "TalosPersistence",
        "TalosUI"
    ]

    /// Reads `Package.swift` as text and returns each `.target(name:
    /// dependencies:)` declaration as a name and its declared dependency
    /// names. Reading the file rather than spawning `swift package
    /// dump-package` keeps this test inside `file.read` — no module besides
    /// `TalosAdapters` may spawn a subprocess, per Architecture: The
    /// Orchestration Boundary § Only the adapter layer spawns a process.
    static func parsePackageGraph() throws -> [String: Set<String>] {
        let packageURL = repositoryRoot.appendingPathComponent("Package.swift")
        let text = try String(contentsOf: packageURL, encoding: .utf8)

        let pattern = #"\.target\(\s*name:\s*"([A-Za-z]+)"\s*(?:,\s*dependencies:\s*\[([^\]]*)\])?\s*\)"#
        let regex = try Regex(pattern)

        var graph: [String: Set<String>] = [:]
        for match in text.matches(of: regex) {
            guard let name = match.output[1].substring.map(String.init) else { continue }
            let depsRaw = match.output[2].substring.map(String.init) ?? ""
            let deps = depsRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
                .filter { !$0.isEmpty }
            graph[name] = Set(deps)
        }
        return graph
    }

    /// Reads `ARCHITECTURE.md` as text and returns each module-table row as a
    /// name and its documented dependency names.
    static func parseArchitectureDocGraph() throws -> [String: Set<String>] {
        let docURL = repositoryRoot.appendingPathComponent("ARCHITECTURE.md")
        let text = try String(contentsOf: docURL, encoding: .utf8)

        let pattern = #"(?m)^\| `([A-Za-z]+)` \| (—|(?:`[A-Za-z]+`(?:, `[A-Za-z]+`)*)) \|"#
        let regex = try Regex(pattern)

        var graph: [String: Set<String>] = [:]
        for match in text.matches(of: regex) {
            guard let name = match.output[1].substring.map(String.init) else { continue }
            let depsRaw = match.output[2].substring.map(String.init) ?? ""
            let deps: [String] = depsRaw == "—" ? [] : depsRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "`")) }
            graph[name] = Set(deps)
        }
        return graph
    }

    /// Walks up from this test file's location to the repository root — the
    /// directory containing `Package.swift` — so the test finds both files
    /// regardless of the working directory `swift test` was invoked from.
    static var repositoryRoot: URL {
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
    @Test("Package.swift declares exactly the seven named modules")
    func packageDeclaresTheSevenModules() throws {
        let graph = try Self.parsePackageGraph()
        #expect(Set(graph.keys) == Self.expectedModuleNames)
    }

    /// > The dependency graph is documented in `ARCHITECTURE.md`
    @Test("ARCHITECTURE.md documents exactly the seven named modules")
    func architectureDocDocumentsTheSevenModules() throws {
        let graph = try Self.parseArchitectureDocGraph()
        #expect(Set(graph.keys) == Self.expectedModuleNames)
    }

    /// > A test asserts the module dependency graph matches the documented
    /// > one.
    @Test("The Package.swift graph matches the ARCHITECTURE.md graph, edge for edge")
    func packageGraphMatchesArchitectureDoc() throws {
        let packageGraph = try Self.parsePackageGraph()
        let docGraph = try Self.parseArchitectureDocGraph()

        for module in Self.expectedModuleNames {
            #expect(packageGraph[module] == docGraph[module], "mismatch for \(module)")
        }
    }

    /// > No module declares a dependency on Foundation's URL loading for
    /// > model providers, or on any model SDK.
    ///
    /// `TalosCore` has no dependencies at all, so nothing reaches a
    /// networking client through the graph without a new edge appearing in
    /// both files — this asserts the base case that makes that true.
    @Test("TalosCore has no dependencies")
    func talosCoreHasNoDependencies() throws {
        let graph = try Self.parsePackageGraph()
        #expect(graph["TalosCore"]?.isEmpty == true)
    }

    /// > an explicit statement of which module may spawn a subprocess (only
    /// > `TalosAdapters`)
    @Test("ARCHITECTURE.md names TalosAdapters as the only module allowed to spawn a subprocess")
    func architectureDocNamesTheOneModuleAllowedToSpawn() throws {
        let docURL = Self.repositoryRoot.appendingPathComponent("ARCHITECTURE.md")
        let text = try String(contentsOf: docURL, encoding: .utf8)
        #expect(text.contains("Only `TalosAdapters` may spawn a subprocess. No other module may."))
    }
}
