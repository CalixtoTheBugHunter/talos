import Foundation

/// Builds the environment a spawned agent CLI is launched with. The child
/// receives only the variables named here, never the parent process's whole
/// environment — so "the spawned environment contains no model API key" stays
/// a property of the construction rather than a denylist someone must keep
/// current. The agent authenticates from its own stored credentials (reached
/// via `HOME`), never from a model-key variable Talos forwards.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
public enum SpawnedAgentEnvironment {
    /// Non-secret operational variables a CLI needs to run in the user's
    /// context — enumerated by what a process legitimately needs, not by what
    /// to strip, so no credential-bearing name appears.
    static let passthroughKeys = [
        "HOME", "USER", "LOGNAME", "SHELL", "TERM", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE"
    ]

    /// The user and package `bin` directories a Finder-launched GUI app does
    /// not inherit on `PATH`; without them an agent CLI installed in one is not
    /// found and the launch fails before it spawns.
    static func pathCandidates(home: String) -> [String] {
        ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
    }

    /// The allowlisted variables present in `source`, plus a `PATH` that keeps
    /// `source`'s entries and appends any missing candidate directory.
    public static func resolve(
        from source: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()
    ) -> [String: String] {
        var environment: [String: String] = [:]
        for key in passthroughKeys {
            if let value = source[key] {
                environment[key] = value
            }
        }
        var entries = (source["PATH"] ?? "").split(separator: ":").map(String.init)
        for candidate in pathCandidates(home: home) where !entries.contains(candidate) {
            entries.append(candidate)
        }
        environment["PATH"] = entries.joined(separator: ":")
        return environment
    }
}
