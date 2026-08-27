import Foundation
import Testing

/// Verifies no provider-specific board vocabulary leaks outside the
/// connector layer — the same way `LogNoNetworkEgressTests` and
/// `ModuleDependencyGraphTests` assert a structural property by reading
/// source text rather than by running the code. `board.yaml` maps a
/// provider's real columns onto Talos's internal states precisely so
/// "no provider-specific assumptions leak into Talos core"; this asserts
/// that nothing outside `TalosProjectLibrary` — the layer that does that
/// translation — hardcodes a provider name or a raw column name instead of
/// reading a ``BoardState``.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#board
@Suite("Board manifest keeps provider vocabulary inside the connector layer")
struct BoardManifestNoProviderLeakTests {
    /// Provider names, plus the raw column-name literals `BoardManifestTests`
    /// fixtures use for the Jira- and GitHub-Projects-shaped configs — the
    /// concrete provider-specific strings a copy-paste could leak.
    private static let providerSpecificSymbols = [
        "jira", "github-projects", "Code Review", "In Progress", "To Do"
    ]

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

    private static var sourceFilesOutsideTheConnectorLayer: [URL] {
        let sourcesRoot = repositoryRoot.appendingPathComponent("Sources")
        guard let enumerator = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil)
        else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            guard !url.pathComponents.contains("TalosProjectLibrary") else { continue }
            files.append(url)
        }
        return files
    }

    @Test("No source file outside TalosProjectLibrary references board-provider vocabulary")
    func noProviderSpecificStringOutsideTheConnectorLayer() throws {
        for url in Self.sourceFilesOutsideTheConnectorLayer {
            let text = try String(contentsOf: url, encoding: .utf8)
            for symbol in Self.providerSpecificSymbols {
                #expect(!text.contains(symbol), "\(url.lastPathComponent) references '\(symbol)'")
            }
        }
    }
}
