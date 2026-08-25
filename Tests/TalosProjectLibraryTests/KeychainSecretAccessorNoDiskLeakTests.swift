import Foundation
@testable import TalosProjectLibrary
import Testing

/// Verifies a secret never reaches disk under `.talos/`, however many reads
/// and writes an accessor performs against a project — the test
/// `Project-Library#where-it-lives`'s "Secrets are never written there"
/// describes.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives
@Suite("A secret never reaches disk under .talos/")
struct KeychainSecretAccessorNoDiskLeakTests {
    private struct AllowingAuthorizer: SecretAccessAuthorizing {
        func authorize(_: SecretAccessAction) throws {
            // Always authorizes.
        }
    }

    private static func temporaryProjectRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private static func makeGitRepository(at root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    /// Every file's contents under `talosRoot`, concatenated, so a single
    /// `contains` check covers the whole tree.
    private static func allFileContents(under talosRoot: URL) throws -> String {
        guard let enumerator = FileManager.default.enumerator(at: talosRoot, includingPropertiesForKeys: nil)
        else { return "" }

        var combined = ""
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            combined += (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        return combined
    }

    @Test("Several read/write cycles against a scaffolded project leave no trace of the secret on disk")
    func readWriteCyclesLeaveNoTraceOnDisk() throws {
        let root = Self.temporaryProjectRoot()
        try Self.makeGitRepository(at: root)
        _ = try ProjectLibraryScaffolder.scaffold(projectRoot: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let project = ProjectIdentifier.generate()
        let accessor = KeychainSecretAccessor(authorizer: AllowingAuthorizer())
        let secretValue = "never-should-touch-disk-\(UUID().uuidString)"
        let references = (0 ..< 5).map { SecretReference(keychainName: "disk-leak-check-\($0)-\(UUID().uuidString)") }
        defer {
            for reference in references {
                try? accessor.delete(reference, project: project)
            }
        }

        for reference in references {
            try accessor.write(reference, project: project, value: secretValue)
            _ = try accessor.read(reference, project: project)
        }

        let talosRoot = root.appendingPathComponent(".talos", isDirectory: true)
        let onDisk = try Self.allFileContents(under: talosRoot)
        #expect(!onDisk.contains(secretValue))
    }
}
