import Foundation
@testable import TalosAdapters
import Testing

/// Verifies ``SpawnedAgentEnvironment`` builds a launch environment by
/// allowlist, so a variable the parent holds but the allowlist does not name
/// never reaches the child.
///
/// § Consequences that must hold at all times —
/// > Talos holds **no** model API keys. Agent CLIs use their own existing
/// > authentication.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
///
/// Proven by shape rather than by naming the variables that must be absent: a
/// denylist would be green for the providers named today and silent on the
/// next, and writing a model-key name into a test file is what `spec-guard`
/// check 3 forbids, since it scans `Tests/` too. A sentinel the allowlist does
/// not carry stands in for every such variable.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#notes-on-the-harder-criteria
@Suite("The spawned agent environment is built by allowlist")
struct SpawnedAgentEnvironmentTests {
    /// A name the allowlist does not carry, standing in for any credential the
    /// user's shell might have exported into the Talos process.
    private static let sentinelKey = "TALOS_ENV_SENTINEL"

    @Test("A source variable the allowlist does not name never reaches the child")
    func dropsUnlistedVariables() {
        let source = ["PATH": "/usr/bin", "HOME": "/Users/example", Self.sentinelKey: "must-not-leak"]

        let resolved = SpawnedAgentEnvironment.resolve(from: source, home: "/Users/example")

        #expect(resolved[Self.sentinelKey] == nil, "an unlisted parent variable leaked into the child")
        #expect(resolved["HOME"] == "/Users/example", "an allowlisted variable must pass through")
    }

    @Test("PATH keeps the source entries and gains the GUI-launch bin directories")
    func augmentsPath() {
        let resolved = SpawnedAgentEnvironment.resolve(from: ["PATH": "/usr/bin"], home: "/Users/example")

        let entries = (resolved["PATH"] ?? "").split(separator: ":").map(String.init)
        #expect(entries.contains("/usr/bin"), "the source PATH entry must be kept")
        #expect(entries.contains("/Users/example/.local/bin"))
        #expect(entries.contains("/opt/homebrew/bin"))
        #expect(entries.filter { $0 == "/usr/bin" }.count == 1, "an already-present entry must not be duplicated")
    }
}
