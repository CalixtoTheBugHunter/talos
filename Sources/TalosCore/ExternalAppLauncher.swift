import Foundation

/// Hands `paths` off to the app named by `bundleIdentifier` — one folder for
/// a terminal at the project path, one or more files for an IDE.
///
/// The seam that keeps `NSWorkspace` (and its `AppKit` import) out of
/// `TalosCore`, the same way an agent adapter keeps its own launch mechanism
/// out of core: the real conformance lives in the `Talos` app target, so
/// this module stays testable without installed apps.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-suite-installs-nothing
public protocol ExternalAppLauncher: Sendable {
    func open(paths: [URL], withAppBundleIdentifier bundleIdentifier: String) throws
}
