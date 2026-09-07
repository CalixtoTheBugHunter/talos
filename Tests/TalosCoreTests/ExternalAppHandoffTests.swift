import Foundation
@testable import TalosCore
import Testing

@Suite("ExternalAppHandoff")
struct ExternalAppHandoffTests {
    private final class RecordingLauncher: ExternalAppLauncher, @unchecked Sendable {
        var opened: (paths: [URL], bundleIdentifier: String)?

        func open(paths: [URL], withAppBundleIdentifier bundleIdentifier: String) throws {
            opened = (paths, bundleIdentifier)
        }
    }

    private struct StubPreferences: ExternalAppPreferenceStoring {
        let configured: ExternalAppCandidate?

        func configuredApp(for _: ExternalAppRole) -> ExternalAppCandidate? {
            configured
        }

        func setConfiguredApp(_: ExternalAppCandidate?, for _: ExternalAppRole) {
            // Never exercised: these tests only read a preconfigured preference.
        }
    }

    @Test("Opening a terminal launches the configured app at the project path")
    func openTerminalLaunchesConfiguredAppAtProjectPath() throws {
        let launcher = RecordingLauncher()
        let iTerm = ExternalAppCandidate(name: "iTerm", bundleIdentifier: "com.googlecode.iterm2")
        let handoff = ExternalAppHandoff(
            resolver: ExternalAppResolver(isInstalled: { $0 == iTerm.bundleIdentifier }),
            preferences: StubPreferences(configured: iTerm),
            launcher: launcher
        )
        let projectPath = URL(fileURLWithPath: "/tmp/some-project")

        try handoff.openTerminal(atProjectPath: projectPath)

        #expect(launcher.opened?.paths == [projectPath])
        #expect(launcher.opened?.bundleIdentifier == iTerm.bundleIdentifier)
    }

    @Test("Opening files in an IDE launches the configured app with exactly those files")
    func openInIDELaunchesConfiguredAppWithFiles() throws {
        let launcher = RecordingLauncher()
        let xcode = ExternalAppCandidate(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
        let handoff = ExternalAppHandoff(
            resolver: ExternalAppResolver(isInstalled: { $0 == xcode.bundleIdentifier }),
            preferences: StubPreferences(configured: xcode),
            launcher: launcher
        )
        let files = [URL(fileURLWithPath: "/tmp/a.swift"), URL(fileURLWithPath: "/tmp/b.swift")]

        try handoff.openInIDE(files: files)

        #expect(launcher.opened?.paths == files)
        #expect(launcher.opened?.bundleIdentifier == xcode.bundleIdentifier)
    }

    @Test("A missing app throws an actionable error and never launches anything")
    func missingAppThrowsActionableErrorAndNeverLaunches() {
        let launcher = RecordingLauncher()
        let handoff = ExternalAppHandoff(
            resolver: ExternalAppResolver(isInstalled: { _ in false }),
            preferences: StubPreferences(configured: nil),
            launcher: launcher
        )

        #expect(throws: MissingExternalAppError.self) {
            try handoff.openTerminal(atProjectPath: URL(fileURLWithPath: "/tmp/some-project"))
        }
        #expect(launcher.opened == nil)
    }
}
