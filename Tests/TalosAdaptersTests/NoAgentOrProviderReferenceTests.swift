import Foundation
import Testing

/// Asserts the adapter contract names no specific agent and no model provider.
///
/// > A protocol naming Claude Code has made agent knowledge core knowledge.
///
/// The rule it holds is § Agent adapters —
/// "**Adding an agent means writing one adapter, never touching Talos core.**"
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#agent-adapters
/// A field, a case, or a doc comment shaped around one agent breaks that claim
/// for whoever writes the second adapter, so it is checked by reading the source
/// rather than remembered by a reviewer.
///
/// Scoped to the contract itself. Once a concrete adapter lands under
/// `Sources/TalosAdapters/`, that adapter names its own agent legitimately and
/// this suite's file list is what keeps the distinction — the contract files
/// below, not the whole module.
@Suite("The adapter contract names no agent and no provider")
struct NoAgentOrProviderReferenceTests {
    /// The files that make up the contract every adapter implements.
    static let contractFiles = [
        "AgentAdapter.swift",
        "AgentEvent.swift",
        "TokenReport.swift",
        "AgentAdapterRegistry.swift",
        "TalosAdapters.swift"
    ]

    /// Lowercased fragments that would make the contract agent-specific or
    /// provider-specific. Matched case-insensitively against the whole file,
    /// comments included: a doc comment shaped around one agent is the same leak
    /// as a field, and it is the one that ships first.
    static let forbiddenFragments = [
        "claude",
        "anthropic",
        "gemini",
        "codex",
        "ollama",
        "openai",
        "bedrock",
        "vertex",
        "mistral"
    ]

    /// Walks up from this file to the directory containing `Package.swift`, so
    /// the suite finds the sources regardless of where `swift test` was run
    /// from. Reading files keeps this inside `file.read`: no module besides
    /// `TalosAdapters` may spawn a subprocess.
    /// § Only the adapter layer spawns a process —
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
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

    static func contractSource(_ fileName: String) throws -> String {
        let url = Self.repositoryRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("TalosAdapters")
            .appendingPathComponent(fileName)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The file list is only meaningful if it matches what is actually there —
    /// a contract file added and not listed would go unchecked.
    @Test("Every file in the adapter module is a listed contract file")
    func everyFileInTheModuleIsListed() throws {
        let moduleURL = Self.repositoryRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("TalosAdapters")
        let present = try FileManager.default
            .contentsOfDirectory(atPath: moduleURL.path)
            .filter { $0.hasSuffix(".swift") }

        #expect(Set(present) == Set(Self.contractFiles))
    }

    @Test("No contract file names a specific agent or model provider", arguments: Self.contractFiles)
    func noContractFileNamesAnAgentOrProvider(fileName: String) throws {
        let source = try Self.contractSource(fileName).lowercased()

        for fragment in Self.forbiddenFragments {
            #expect(!source.contains(fragment), "\(fileName) names '\(fragment)'")
        }
    }
}
