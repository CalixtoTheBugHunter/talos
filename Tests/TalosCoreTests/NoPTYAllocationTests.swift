import Foundation
import Testing

/// Asserts no file in the repository references a PTY-allocation primitive.
///
/// > It is deliberately **not a PTY**. There is no embedded shell tab.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is-not
///
/// `spec-guard.sh` exempts `Sources/TalosAdapters/` from its own PTY check the
/// same way it exempts that module from the subprocess-spawn check — its own
/// header states it plainly: "It does not check for PTY allocation *inside*
/// the adapter module." This test carries no such exemption, so it is what
/// actually makes "not a PTY" unconditional: the adapter streams a spawned
/// agent's output over pipes, and nothing anywhere needs a PTY.
///
/// Walks the repository rather than a fixed file list, so a PTY primitive
/// landing in a file nobody added to a list still fails this test — the same
/// reasoning `tools/spec-guard/spec-guard.sh` states for scanning tracked
/// files rather than a maintained exclusion list. This is a Swift-level,
/// permanent-property check alongside that CI grep, not a replacement for it.
@Suite("No PTY allocation anywhere in the repository")
struct NoPTYAllocationTests {
    /// The primitives `tools/spec-guard/spec-guard.sh` already forbids
    /// outside the adapter layer — kept in sync by citing the same rule
    /// rather than by any shared source, since one is Swift and the other is
    /// a CI grep.
    ///
    /// Each is joined from two halves that individually match none of
    /// `spec-guard.sh`'s own PTY alternatives, so this file's own literals
    /// do not trip that CI check the way a plain array of them would — the
    /// same non-contiguous-parts technique § A scanner's self-test never
    /// commits its fixture whole uses for the same shape of problem.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards
    static let forbiddenFragments = [
        "fork" + "pty", "open" + "pty", "posix_" + "openpt", "login_" + "tty",
        "pts" + "name", "grant" + "pt", "unlock" + "pt", "/dev/" + "ptmx", "/dev/" + "pty"
    ]

    static let skippedDirectoryNames: Set<String> = [".git", ".build", ".swiftpm", "DerivedData"]

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

    /// Every `.swift` file in the repository except this one — which
    /// necessarily contains the primitives above as string literals to
    /// forbid them, the same structural reason `spec-guard.sh` excludes its
    /// own directory from its own scan.
    static var scannedSwiftFiles: [URL] {
        let root = repositoryRoot
        let selfPath = URL(fileURLWithPath: #filePath).standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                if Self.skippedDirectoryNames.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard url.pathExtension == "swift" else { continue }
            guard url.standardizedFileURL.path != selfPath else { continue }
            files.append(url)
        }
        return files
    }

    /// Catches the regression this suite exists to prevent: a PTY primitive
    /// landing anywhere, including inside the adapter module — a place the
    /// CI grep's own header states it deliberately does not check.
    @Test("No Swift file references a PTY-allocation primitive")
    func noFileReferencesAPTYPrimitive() throws {
        let files = Self.scannedSwiftFiles
        // A discovery that found nothing would make the assertion below vacuous.
        #expect(!files.isEmpty)

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for fragment in Self.forbiddenFragments {
                #expect(!source.contains(fragment), "\(file.path) references '\(fragment)'")
            }
        }
    }
}
