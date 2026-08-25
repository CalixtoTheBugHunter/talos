import Foundation
import Testing

/// Verifies no log destination is a network endpoint, the same way
/// `ModuleDependencyGraphTests` asserts a structural property by reading
/// source text rather than by running the code: a networking symbol either
/// appears in the logging sources or it does not, and that is true
/// regardless of which destination it would have reached.
///
/// Named symbols, not a general secret/network scanner: this list is
/// Foundation/Network-framework client types plus the raw POSIX socket
/// calls a hand-rolled client would use instead. A novel networking
/// mechanism this list doesn't name would pass silently — the same
/// disclosed limitation `tools/spec-guard/spec-guard.sh` states about its
/// own pattern matching.
@Suite("Logging has no network egress")
struct LogNoNetworkEgressTests {
    private static let networkingSymbols = [
        "URLSession", "URLRequest", "NWConnection", "NWListener",
        "Socket(", "CFSocket", "dispatch_io_create", "InputStream(url:",
        "socket(", "connect(", "send(", "recv("
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

    private static var loggingSourceFiles: [URL] {
        let dir = repositoryRoot.appendingPathComponent("Sources/TalosCore")
        let names = ["Log.swift", "LogRedaction.swift", "LogExporter.swift"]
        return names.map { dir.appendingPathComponent($0) }
    }

    @Test("No logging source file references a networking API")
    func loggingSourcesContainNoNetworkingSymbol() throws {
        for fileURL in Self.loggingSourceFiles {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            for symbol in Self.networkingSymbols {
                #expect(!text.contains(symbol), "\(fileURL.lastPathComponent) references \(symbol)")
            }
        }
    }
}
