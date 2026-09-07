import AppKit
import Foundation
import TalosCore

/// `NSWorkspace`-backed hand-off: asks Launch Services to open `paths` with
/// the named app, the same mechanism as dragging a folder onto an app's
/// Dock icon. Never `Process` — that spawn path is confined to
/// `TalosAdapters`.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
struct NSWorkspaceExternalAppLauncher: ExternalAppLauncher {
    func open(paths: [URL], withAppBundleIdentifier bundleIdentifier: String) throws {
        guard let appURL = Self.appURL(forBundleIdentifier: bundleIdentifier) else {
            throw ExternalAppLaunchFailed(bundleIdentifier: bundleIdentifier)
        }
        NSWorkspace.shared.open(paths, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    static func appURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    static func isInstalled(bundleIdentifier: String) -> Bool {
        appURL(forBundleIdentifier: bundleIdentifier) != nil
    }
}

/// Thrown when an app resolved as installed can no longer be found at
/// launch time — the race between the detection check and the open call.
/// Distinct from ``MissingExternalAppError``, which is the ordinary "never
/// installed" case.
struct ExternalAppLaunchFailed: Error {
    let bundleIdentifier: String
}
