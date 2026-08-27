import Foundation
import Testing

/// Verifies no second code path to the Keychain exists outside
/// ``KeychainSecretAccessor`` — the same way `BoardManifestNoProviderLeakTests`
/// and `ModuleDependencyGraphTests` assert a structural property by reading
/// source text rather than by running the code.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution#decisions
@Suite("Keychain secret accessor is the only path to the Keychain")
struct KeychainSecretAccessorNoSecondPathTests {
    /// `SecItem` covers every `Security` framework Keychain call
    /// (`SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`,
    /// `SecItemDelete`) with one substring, since all four share that
    /// prefix.
    private static let keychainAPISymbols = ["SecItem", "import Security"]

    private static let accessorFileName = "KeychainSecretAccessor.swift"

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

    private static var sourceFilesOutsideTheAccessor: [URL] {
        let sourcesRoot = repositoryRoot.appendingPathComponent("Sources")
        guard let enumerator = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil)
        else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            guard url.lastPathComponent != accessorFileName else { continue }
            files.append(url)
        }
        return files
    }

    @Test("No source file other than KeychainSecretAccessor.swift touches the Security framework's Keychain API")
    func noOtherSourceFileTouchesTheKeychainAPI() throws {
        for url in Self.sourceFilesOutsideTheAccessor {
            let text = try String(contentsOf: url, encoding: .utf8)
            for symbol in Self.keychainAPISymbols {
                #expect(!text.contains(symbol), "\(url.lastPathComponent) references '\(symbol)'")
            }
        }
    }
}
