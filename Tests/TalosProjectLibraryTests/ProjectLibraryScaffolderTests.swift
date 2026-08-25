import Foundation
@testable import TalosProjectLibrary
import Testing

/// Verifies `.talos/` scaffolding against
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives.
@Suite("Project Library scaffolder")
struct ProjectLibraryScaffolderTests {
    /// A fresh temporary directory per test, so parallel tests never share a
    /// project root.
    private static func temporaryProjectRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    /// Makes `root` look like a git repository, the same shape `git init`
    /// leaves — a `.git` directory is enough for the scaffolder's own check,
    /// which only tests for the entry's existence.
    private static func makeGitRepository(at root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    /// Every relative path under `.talos/` that actually exists on disk,
    /// files and directories both, relative to `talosRoot`. Compares
    /// `pathComponents` rather than stripping a string prefix, because the
    /// enumerator resolves `/var`'s symlink to `/private/var` while
    /// `talosRoot`'s own path does not, which a prefix strip would miss.
    private static func actualRelativePaths(under talosRoot: URL) throws -> Set<String> {
        guard let enumerator = FileManager.default.enumerator(at: talosRoot, includingPropertiesForKeys: nil) else {
            return []
        }
        let rootDepth = talosRoot.standardizedFileURL.pathComponents.count
        var paths: Set<String> = []
        for case let url as URL in enumerator {
            let components = url.standardizedFileURL.pathComponents
            paths.insert(components[rootDepth...].joined(separator: "/"))
        }
        return paths
    }

    @Test("Scaffolding a fresh repository creates exactly the SPEC tree")
    func createsExactlyTheSpecTree() throws {
        let root = Self.temporaryProjectRoot()
        try Self.makeGitRepository(at: root)

        let result = try ProjectLibraryScaffolder.scaffold(projectRoot: root)

        #expect(Set(result.created) == Set(ProjectLibraryScaffolder.specifiedRelativePaths))
        #expect(result.alreadyPresent.isEmpty)

        let talosRoot = root.appendingPathComponent(".talos", isDirectory: true)
        let onDisk = try Self.actualRelativePaths(under: talosRoot)
        #expect(onDisk == Set(ProjectLibraryScaffolder.specifiedRelativePaths + ["guidelines"]))
    }

    @Test(".gitignore ignores local/")
    func gitignoreIgnoresLocal() throws {
        let root = Self.temporaryProjectRoot()
        try Self.makeGitRepository(at: root)
        _ = try ProjectLibraryScaffolder.scaffold(projectRoot: root)

        let contents = try String(
            contentsOf: root.appendingPathComponent(".talos/.gitignore"),
            encoding: .utf8
        )
        #expect(contents.contains("local/"))
    }

    /// Checks the comment marker and the SPEC link specifically, rather than
    /// only non-emptiness — a regression that replaced a header with
    /// arbitrary non-comment text, or dropped the link, would pass a bare
    /// "is not empty" assertion.
    @Test("Every generated file opens with an explanatory comment linking the SPEC")
    func generatedFilesCarryExplanatoryComments() throws {
        let root = Self.temporaryProjectRoot()
        try Self.makeGitRepository(at: root)
        _ = try ProjectLibraryScaffolder.scaffold(projectRoot: root)

        let talosRoot = root.appendingPathComponent(".talos", isDirectory: true)
        for path in ProjectLibraryScaffolder.specifiedRelativePaths {
            let url = talosRoot.appendingPathComponent(path)
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
            guard !isDirectory.boolValue else { continue }

            let contents = try String(contentsOf: url, encoding: .utf8)
            let commentMarker = path.hasSuffix(".md") ? "<!--" : "#"
            #expect(
                contents.hasPrefix(commentMarker),
                "\(path) does not open with an explanatory comment (\(commentMarker))"
            )
            #expect(
                contents.contains("https://github.com/CalixtoTheBugHunter/talos/wiki/"),
                "\(path) has no SPEC link a reader can follow without docs"
            )
        }
    }

    @Test("Running scaffold twice never clobbers an edited file and adds nothing new")
    func idempotentAndNeverClobbers() throws {
        let root = Self.temporaryProjectRoot()
        try Self.makeGitRepository(at: root)
        _ = try ProjectLibraryScaffolder.scaffold(projectRoot: root)

        let projectYAMLURL = root.appendingPathComponent(".talos/project.yaml")
        let userEdit = "# edited by the user\nname: my-project\n"
        try userEdit.write(to: projectYAMLURL, atomically: true, encoding: .utf8)

        let second = try ProjectLibraryScaffolder.scaffold(projectRoot: root)

        #expect(second.created.isEmpty)
        #expect(Set(second.alreadyPresent) == Set(ProjectLibraryScaffolder.specifiedRelativePaths))

        let survivingContents = try String(contentsOf: projectYAMLURL, encoding: .utf8)
        #expect(survivingContents == userEdit)
    }

    @Test("Scaffolding outside a git repository throws a clear error")
    func refusesOutsideGitRepository() throws {
        let root = Self.temporaryProjectRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        #expect(throws: ProjectLibraryScaffolder.ScaffoldError.notAGitRepository(path: root.path)) {
            try ProjectLibraryScaffolder.scaffold(projectRoot: root)
        }
    }
}
