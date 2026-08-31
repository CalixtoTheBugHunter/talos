import Foundation
import Testing

/// "No AI-reachable code path can write to the allowlist store."
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
///
/// Everything that reaches the gate — every adapter, the gate itself, the
/// session pipeline — only ever needs the read path, `isAllowlisted`, which
/// `SafeguardsGate` already depends on through the ``SafeguardsAllowlist``
/// protocol. Nothing agent-facing has a legitimate reason to call
/// `AllowlistStore`'s two mutators, so this asserts that structurally rather
/// than trusting that no caller will be added later: it greps every source
/// file for the two distinctive write-method names, the same technique
/// `NoAgentOrProviderReferenceTests` and `NoPollingTimerTests` use for their
/// own structural absences.
@Suite("No source file writes to the allowlist store except its own definition")
struct AllowlistStoreWriteReachabilityTests {
    /// The only file permitted to reference either write method — its own
    /// declaration and internal calls between the two.
    static let definitionFile = "AllowlistStore.swift"

    static let writeMethodNames = ["allowlistAction(", "revokeAllowlistedAction("]

    /// Walks up from this file to the directory containing `Package.swift`,
    /// the same pattern every other structural-absence test in this repo
    /// uses to find `Sources/` regardless of the working directory `swift
    /// test` was invoked from.
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

    @Test("No file under Sources/, other than AllowlistStore.swift, names a write method")
    func noOtherSourceFileNamesAWriteMethod() throws {
        let sourcesRoot = Self.repositoryRoot.appendingPathComponent("Sources")
        guard let enumerator = FileManager.default.enumerator(
            at: sourcesRoot, includingPropertiesForKeys: nil
        ) else {
            Issue.record("Could not enumerate \(sourcesRoot.path)")
            return
        }

        for case let url as URL in enumerator {
            guard url.pathExtension == "swift", url.lastPathComponent != Self.definitionFile else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            for methodName in Self.writeMethodNames {
                let message = "\(url.path) references '\(methodName)' — only \(Self.definitionFile) " +
                    "may write to the allowlist store"
                #expect(!source.contains(methodName), "\(message)")
            }
        }
    }
}
