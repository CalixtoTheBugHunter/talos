import Foundation

/// Creates the `.talos/` directory tree Project Library § Where it lives
/// specifies file-by-file, when a project is added.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives
///
/// https://github.com/CalixtoTheBugHunter/talos/issues/41
public enum ProjectLibraryScaffolder {
    /// One `.talos/` entry the SPEC names, in the order
    /// [§ Where it lives](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives)
    /// lists it.
    private struct Entry {
        let relativePath: String
        let isDirectory: Bool
        let contents: String?
    }

    /// The explanatory comment a generated YAML file carries, so it is
    /// "editable without docs" per issue #41's acceptance criteria — the
    /// exact one-line purpose the SPEC tree already gives that file.
    private static func yamlHeader(purpose: String) -> String {
        """
        # \(purpose)
        # https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives

        """
    }

    /// `safeguards.md` deliberately carries no context priority order. Per
    /// Talos Guidelines § Where the order is declared: "Talos does not write
    /// the default into the project: `safeguards.md` is the one file nothing
    /// may modify but the user, and generating a default into it would have
    /// Talos performing the write the taxonomy refuses."
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#where-the-order-is-declared
    private static let safeguardsContents = """
    <!--
    Project safeguards — the highest-authority project-level document.
    Never editable by AI. See:
    https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#safeguards

    This file also declares the project's context priority order — the order
    assembled context is dropped in when it exceeds a sub-function's token
    ceiling. Talos never writes a default order here; leave this section
    unset until you decide one:
    https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#where-the-order-is-declared
    -->

    """

    /// Shared header for a `guidelines/*.md` file. Each Editable Talos
    /// Guideline "declares" these four things per Talos Guidelines §
    /// Editable Talos Guidelines:
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#editable-talos-guidelines
    private static func guidelineContents(subFunction: String, status: String) -> String {
        """
        <!--
        \(subFunction) guideline — \(status).
        https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#editable-talos-guidelines

        Declare, below, this sub-function's:
        - purpose
        - the context it wants assembled
        - its token ceiling
        - its output expectations
        -->

        """
    }

    /// The exact tree
    /// [§ Where it lives](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives)
    /// specifies, in its own order. `local/` is a directory only — its
    /// contents are runtime-derived and never scaffolded.
    private static let tree: [Entry] = [
        Entry(relativePath: "project.yaml", isDirectory: false,
              contents: yamlHeader(purpose: "project identity, which agents, which sub-functions enabled")),
        Entry(relativePath: "agents.yaml", isDirectory: false,
              contents: yamlHeader(purpose: "agent adapters + MCP/CLI wiring (references to secrets, never secrets)")),
        Entry(relativePath: "spec.yaml", isDirectory: false,
              contents: yamlHeader(purpose: "Spec Drive location(s) and sync rules")),
        Entry(relativePath: "connectors.yaml", isDirectory: false,
              contents: yamlHeader(purpose: "repo, monitoring, deployment, testing connections")),
        Entry(relativePath: "board.yaml", isDirectory: false,
              contents: yamlHeader(purpose: "board provider + column/state mapping")),
        Entry(relativePath: "safeguards.md", isDirectory: false, contents: safeguardsContents),
        Entry(relativePath: "guidelines", isDirectory: true, contents: nil),
        Entry(relativePath: "guidelines/assistant.md", isDirectory: false,
              contents: guidelineContents(subFunction: "Assistant", status: "active at MVP")),
        Entry(relativePath: "guidelines/automator.md", isDirectory: false,
              contents: guidelineContents(subFunction: "Automator", status: "active at MVP")),
        Entry(relativePath: "guidelines/advisor.md", isDirectory: false,
              contents: guidelineContents(subFunction: "Advisor", status: "present but inert")),
        Entry(relativePath: "guidelines/self-improver.md", isDirectory: false,
              contents: guidelineContents(subFunction: "Self-improver", status: "present but inert")),
        Entry(relativePath: ".gitignore", isDirectory: false, contents: """
        # `local/` holds durable local memories and derived, rebuildable
        # indexes/caches. Never committed:
        # https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives
        local/

        """),
        Entry(relativePath: "local", isDirectory: true, contents: nil)
    ]

    /// Every relative path this scaffolder ever creates, in SPEC order — what
    /// a test compares the generated tree against.
    public static var specifiedRelativePaths: [String] {
        tree.map(\.relativePath)
    }

    /// Failures that stop scaffolding rather than working around it.
    public enum ScaffoldError: Error, Equatable {
        /// No `.git` entry was found walking up from `projectRoot`.
        case notAGitRepository(path: String)
    }

    /// What one call to ``scaffold(projectRoot:fileManager:)`` did, so a
    /// caller can report it — never silently.
    public struct ScaffoldResult: Equatable, Sendable {
        /// Relative paths newly created by this call.
        public let created: [String]
        /// Relative paths that already existed and were left untouched.
        public let alreadyPresent: [String]
    }

    /// Creates `.talos/` under `projectRoot` with exactly the entries
    /// Project Library § Where it lives specifies. Idempotent: an entry that
    /// already exists is left untouched and reported in
    /// ``ScaffoldResult/alreadyPresent``, never overwritten — this is what
    /// makes running it on an existing `.talos/` never clobber a user's
    /// edits.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives
    ///
    /// Throws ``ScaffoldError/notAGitRepository(path:)`` when `projectRoot`
    /// is not inside a git repository. Checked by walking the filesystem
    /// rather than spawning `git`, because only `TalosAdapters` may spawn a
    /// subprocess — see "Only the adapter layer spawns a process" in
    /// Architecture: The Orchestration Boundary.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
    public static func scaffold(
        projectRoot: URL,
        fileManager: FileManager = .default
    ) throws -> ScaffoldResult {
        guard isInsideGitRepository(startingAt: projectRoot, fileManager: fileManager) else {
            throw ScaffoldError.notAGitRepository(path: projectRoot.path)
        }

        let talosRoot = projectRoot.appendingPathComponent(".talos", isDirectory: true)
        try fileManager.createDirectory(at: talosRoot, withIntermediateDirectories: true)

        var created: [String] = []
        var alreadyPresent: [String] = []

        for entry in tree {
            let url = talosRoot.appendingPathComponent(entry.relativePath, isDirectory: entry.isDirectory)
            if fileManager.fileExists(atPath: url.path) {
                alreadyPresent.append(entry.relativePath)
                continue
            }

            if entry.isDirectory {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                let parent = url.deletingLastPathComponent()
                if !fileManager.fileExists(atPath: parent.path) {
                    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                let data = Data((entry.contents ?? "").utf8)
                fileManager.createFile(atPath: url.path, contents: data)
            }
            created.append(entry.relativePath)
        }

        return ScaffoldResult(created: created, alreadyPresent: alreadyPresent)
    }

    /// Walks up from `directory` looking for a `.git` entry — a directory
    /// for a normal clone, a file for a worktree or submodule. Bounded by
    /// `pathComponents.count` rather than comparing successive
    /// `deletingLastPathComponent()` results for equality: at the root, that
    /// comparison never converges on this platform's `URL` implementation,
    /// which keeps prepending `..` instead of returning the same path twice.
    private static func isInsideGitRepository(startingAt directory: URL, fileManager: FileManager) -> Bool {
        var current = directory.standardizedFileURL
        for _ in 0 ..< current.pathComponents.count {
            let gitPath = current.appendingPathComponent(".git", isDirectory: false).path
            if fileManager.fileExists(atPath: gitPath) {
                return true
            }
            current = current.deletingLastPathComponent()
        }
        return false
    }
}
