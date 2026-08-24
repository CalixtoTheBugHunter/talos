import Foundation
@testable import TalosProjectLibrary
import Testing

/// Verifies `.talos/` scaffolding against
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives.
///
/// https://github.com/CalixtoTheBugHunter/talos/issues/41
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

    /// > Scaffolding creates exactly the tree in the SPEC: `project.yaml`,
    /// > `agents.yaml`, `spec.yaml`, `connectors.yaml`, `board.yaml`,
    /// > `safeguards.md`,
    /// > `guidelines/{assistant,advisor,automator,self-improver}.md`,
    /// > `.gitignore`, `local/`
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

    /// > `.talos/.gitignore` ignores `local/`
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

    /// > Generated files carry explanatory comments so they are editable
    /// > without docs
    @Test("Every generated file is non-empty")
    func generatedFilesCarryContent() throws {
        let root = Self.temporaryProjectRoot()
        try Self.makeGitRepository(at: root)
        _ = try ProjectLibraryScaffolder.scaffold(projectRoot: root)

        let talosRoot = root.appendingPathComponent(".talos", isDirectory: true)
        for path in ProjectLibraryScaffolder.specifiedRelativePaths {
            let url = talosRoot.appendingPathComponent(path)
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
            if !isDirectory.boolValue {
                let contents = try String(contentsOf: url, encoding: .utf8)
                #expect(!contents.isEmpty, "\(path) has no explanatory content")
            }
        }
    }

    /// > Scaffolding is idempotent — running it on an existing `.talos/`
    /// > never clobbers user edits and reports what it would add
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

    /// > Scaffolding refuses to run outside a git repository, with a clear
    /// > reason
    @Test("Scaffolding outside a git repository throws a clear error")
    func refusesOutsideGitRepository() throws {
        let root = Self.temporaryProjectRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        #expect(throws: ProjectLibraryScaffolder.ScaffoldError.notAGitRepository(path: root.path)) {
            try ProjectLibraryScaffolder.scaffold(projectRoot: root)
        }
    }
}
