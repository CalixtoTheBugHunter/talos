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
/// Scoped to the contract itself, and the scope is a **directory rule** rather
/// than a list to maintain: the contract is every `.swift` file at the root of
/// `Sources/TalosAdapters/`, and a concrete adapter lives in a subdirectory of
/// its own, where it names its own agent legitimately. Stated as a rule because
/// a list would have to be edited by every adapter author, and the edit that
/// makes the list pass is the edit that stops it checking anything.
@Suite("The adapter contract names no agent and no provider")
struct NoAgentOrProviderReferenceTests {
    /// The contract every adapter implements, plus the machinery every adapter
    /// shares — every `.swift` file at the module root, asserted to be exactly
    /// these by ``everyRootFileIsAListedContractFile()``. Shared machinery is
    /// held to the same rule as the protocol: an agent named inside the one
    /// type that spawns a process is agent knowledge in the layer every adapter
    /// depends on.
    static let contractFiles = [
        "AgentAdapter.swift",
        "AgentEvent.swift",
        "AgentProcess.swift",
        "AgentProcessEvent.swift",
        "AgentOutputDecoder.swift",
        "ProcessSpawn.swift",
        "ChannelState.swift",
        "ProcessEventQueue.swift",
        "ReadSource.swift",
        "WaitStatus.swift",
        "TokenReport.swift",
        "AgentAdapterRegistry.swift",
        "TalosAdapters.swift"
    ]

    /// Lowercased fragments that would make the contract agent-specific or
    /// provider-specific. Matched case-insensitively against the whole file,
    /// comments included: a doc comment shaped around one agent is the same leak
    /// as a field, and it is the one that ships first.
    /// The first five are the providers § Consequences that must hold at all
    /// times names one by one — "Talos ships **no** API client for Anthropic,
    /// Google, Amazon Bedrock, OpenAI, or Ollama" — so a list missing one of
    /// them was green on the exact case the SPEC line enumerates.
    static let forbiddenFragments = [
        "anthropic",
        "google",
        "amazon",
        "openai",
        "ollama",
        "claude",
        "gemini",
        "codex",
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

    static var moduleURL: URL {
        repositoryRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("TalosAdapters")
    }

    /// The file list is only meaningful if it matches what is actually there —
    /// a contract file added and not listed would go unchecked. Scoped to the
    /// module root, so landing a concrete adapter does not require relaxing
    /// this assertion.
    @Test("Every file at the module root is a listed contract file")
    func everyRootFileIsAListedContractFile() throws {
        let present = try FileManager.default
            .contentsOfDirectory(at: Self.moduleURL, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { $0.pathExtension == "swift" }
            .map(\.lastPathComponent)

        #expect(Set(present) == Set(Self.contractFiles))
    }

    /// A contract file in a subdirectory would be read by neither assertion
    /// above, so the directory rule is checked rather than assumed: the only
    /// thing a subdirectory may hold is a concrete adapter, and a concrete
    /// adapter is not the contract.
    ///
    /// The regression this asserts: moving a contract type into
    /// `Sources/TalosAdapters/<anything>/` would silently exempt it from the
    /// fragment check, which a non-recursive listing could not see.
    @Test("No subdirectory of the module holds a file named like the contract")
    func noSubdirectoryHoldsAContractFile() {
        let enumerated = FileManager.default.enumerator(atPath: Self.moduleURL.path)
        let nested = (enumerated?.allObjects as? [String] ?? [])
            .filter { $0.hasSuffix(".swift") && $0.contains("/") }

        for path in nested {
            let fileName = (path as NSString).lastPathComponent
            #expect(
                !Self.contractFiles.contains(fileName),
                "\(path) shadows contract file \(fileName) outside the checked root"
            )
        }
    }

    @Test("No contract file names a specific agent or model provider", arguments: Self.contractFiles)
    func noContractFileNamesAnAgentOrProvider(fileName: String) throws {
        let source = try Self.contractSource(fileName).lowercased()

        for fragment in Self.forbiddenFragments {
            #expect(!source.contains(fragment), "\(fileName) names '\(fragment)'")
        }
    }
}
