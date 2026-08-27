import Foundation

/// Thrown from `launch` when no `claude` executable is found on `PATH`.
/// Distinct from ``AgentSpawnFailure``, which is `AgentProcess`'s own report of
/// a `posix_spawn` that failed after a path was already found — this is the
/// case that path never existed.
struct ClaudeCodeNotInstalledError: Error, Equatable, Sendable {
    let fix: String

    init(searchedPath: String) {
        fix = "Could not find '\(ClaudeCodeInstallCheck.executableName)' on PATH (\(searchedPath)). " +
            "Install Claude Code (https://claude.com/download), or set 'command:' in .talos/agents.yaml to its path."
    }
}

/// Detects a missing Claude Code install before spawning, and feature-detects
/// a version gap after via `system/init`'s own `capabilities` list.
///
/// No minimum version is hardcoded for either — a missing install stops the
/// run, a version gap does not.
enum ClaudeCodeInstallCheck {
    static let executableName = "claude"

    /// Resolves `claude` against `environment["PATH"]` — the child's own
    /// complete environment, not Talos's. `AgentProcess` takes only an
    /// absolute path; resolving a name is the adapter's own work.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#agent-adapters
    static func resolveExecutablePath(
        environment: [String: String],
        fileManager: FileManager = .default
    ) throws -> String {
        let searchPath = environment["PATH"] ?? ""
        for directory in searchPath.split(separator: ":") {
            let candidate = "\(directory)/\(executableName)"
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        throw ClaudeCodeNotInstalledError(searchedPath: searchPath)
    }

    /// A diagnostic for a `system/init` reporting no `capabilities` list —
    /// a build this adapter's parse was never verified against. Reported,
    /// not raised: the run continues.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions
    static func missingCapabilitiesDiagnostic(version: String) -> String {
        let named = version.isEmpty ? "This Claude Code install" : "Claude Code \(version)"
        return "\(named) did not report a capabilities list. Talos has verified this adapter against " +
            "Claude Code 2.1.246 and later; behavior on an older or different build is not guaranteed."
    }
}
