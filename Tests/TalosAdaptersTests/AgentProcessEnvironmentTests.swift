import Foundation
@testable import TalosAdapters
import Testing

/// Verifies that a spawned agent CLI gets exactly the environment it was given
/// and nothing else.
///
/// § Consequences that must hold at all times —
/// > Talos holds **no** model API keys. Agent CLIs use their own existing
/// > authentication.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
///
/// Exact equality rather than naming the variables that must be absent: a list
/// would be green for the providers § Consequences enumerates and silent on the
/// next one, and writing those names into a test file is what `spec-guard` check
/// 3 forbids, since it scans `Tests/` too. Equality needs no list.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#notes-on-the-harder-criteria
///
/// Catches the default nobody writes deliberately — inheriting the parent's
/// environment, which holds whatever the user's shell exported.
@Suite("The spawned environment is exactly what was configured")
struct AgentProcessEnvironmentTests {
    /// Prints the child's environment, one `NAME=value` per line. Reachable on
    /// every macOS, so § The suite installs nothing holds.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-suite-installs-nothing
    static let environmentReporter = "/usr/bin/env"

    /// Set for the test process and absent from the configuration below, so
    /// inheritance is detectable rather than merely unlikely.
    static let inheritedOnlyVariable = "HOME"

    /// A `PATH` and one project-scoped variable. No secret, because there is none
    /// to pass — the agent CLI authenticates itself.
    static func configuration() -> AgentLaunchConfiguration {
        AgentLaunchConfiguration(
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            environment: ["PATH": "/usr/bin:/bin", "TALOS_SESSION": "environment-test"]
        )
    }

    /// Parses `env` output back into a dictionary. A value containing `=` keeps
    /// it: only the first separator divides a name from its value.
    static func parse(_ output: String) -> [String: String] {
        var environment: [String: String] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let separator = line.firstIndex(of: "=") else { continue }
            environment[String(line[line.startIndex ..< separator])] =
                String(line[line.index(after: separator)...])
        }
        return environment
    }

    static func childEnvironment() async throws -> [String: String] {
        let process = AgentProcess(
            executablePath: environmentReporter,
            configuration: configuration()
        )
        let events = try await AgentProcessTests.collect(process.start())
        return parse(AgentProcessTests.text(events, on: .standardOutput))
    }

    @Test("The child's environment equals the configured one exactly")
    func theChildSeesExactlyTheConfiguredEnvironment() async throws {
        let child = try await Self.childEnvironment()

        #expect(child == Self.configuration().environment)
    }

    /// The same claim from the other side — the one that fails when equality
    /// above breaks by an addition rather than an omission.
    @Test("A variable the parent holds and the configuration omits does not reach the child")
    func aParentVariableDoesNotReachTheChild() async throws {
        // If the variable were unset in the parent too, its absence in the child
        // would prove nothing.
        #expect(ProcessInfo.processInfo.environment[Self.inheritedOnlyVariable] != nil)
        #expect(Self.configuration().environment[Self.inheritedOnlyVariable] == nil)

        let child = try await Self.childEnvironment()

        #expect(child[Self.inheritedOnlyVariable] == nil, "the child inherited the parent's environment")
    }
}
