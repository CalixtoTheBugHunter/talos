import Foundation
@testable import TalosAdapters
import Testing

/// Asserts AC8's decision — detect a *missing* install and report it
/// actionably, with no version floor — driven entirely through an injected
/// `PATH`. No `which`, no probe of the real install, no skip.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-suite-installs-nothing
@Suite("Claude Code install check")
struct ClaudeCodeInstallCheckTests {
    @Test("Resolves the executable from an injected PATH, not the real one")
    func resolvesFromInjectedPath() throws {
        let directory = NSTemporaryDirectory() + "talos-claude-code-install-check-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let executablePath = directory + "/claude"
        try "#!/bin/sh\nexit 0\n".write(toFile: executablePath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executablePath)

        let resolved = try ClaudeCodeInstallCheck.resolveExecutablePath(environment: ["PATH": directory])
        #expect(resolved == executablePath)
    }

    @Test("A PATH with no matching executable fails, naming a fix, rather than being skipped")
    func missingExecutableFailsRatherThanSkipping() {
        let emptyDirectory = NSTemporaryDirectory() + "talos-claude-code-install-check-empty-\(UUID().uuidString)"
        #expect(throws: ClaudeCodeNotInstalledError.self) {
            _ = try ClaudeCodeInstallCheck.resolveExecutablePath(environment: ["PATH": emptyDirectory])
        }
    }

    @Test("A missing capabilities list names the version it was seen on")
    func missingCapabilitiesDiagnosticNamesVersion() {
        let message = ClaudeCodeInstallCheck.missingCapabilitiesDiagnostic(version: "1.0.0")
        #expect(message.contains("1.0.0"))
    }

    @Test("A missing capabilities list with no known version still names something readable")
    func missingCapabilitiesDiagnosticWithoutVersion() {
        let message = ClaudeCodeInstallCheck.missingCapabilitiesDiagnostic(version: "")
        #expect(!message.isEmpty)
    }
}
