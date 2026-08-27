import Foundation
import Testing

/// Asserts the files this issue adds never open an MCP connection themselves
/// — "Talos ships **no** MCP client of its own. MCP servers are configured
/// *for the agent*; Talos writes that configuration and reads its results."
///
/// Repo-wide MCP client dependency and import shapes are `spec-guard`'s own
/// job, unchanged by this file. This test is narrower and reads by
/// source rather than by network behavior, the same style
/// `NoAgentOrProviderReferenceTests` and `NoPollingTimerTests` already use:
/// these specific files only ever write JSON to disk and hand a path to the
/// adapter's own invocation, so a network or MCP-client primitive appearing
/// in either is the regression this guards.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
@Suite("MCP configuration is written, never connected to")
struct NoMCPConnectionTests {
    static let filesThatWriteMCPConfiguration = [
        "ClaudeCode/ClaudeCodeMCPConfiguration.swift",
        "ClaudeCode/ClaudeCodeInvocation.swift"
    ]

    static let forbiddenFragments = [
        "urlsession",
        "urlrequest",
        "nwconnection",
        "import network",
        "modelcontextprotocol",
        "jsonrpc",
        "json-rpc"
    ]

    static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        fatalError("Could not locate the repository root above \(#filePath)")
    }

    static func source(_ relativePath: String) throws -> String {
        let url = Self.repositoryRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("TalosAdapters")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test(
        "No file that writes MCP configuration names a connection primitive",
        arguments: Self.filesThatWriteMCPConfiguration
    )
    func noFileNamesAConnectionPrimitive(relativePath: String) throws {
        let source = try Self.source(relativePath).lowercased()

        for fragment in Self.forbiddenFragments {
            #expect(!source.contains(fragment), "\(relativePath) names '\(fragment)'")
        }
    }
}
