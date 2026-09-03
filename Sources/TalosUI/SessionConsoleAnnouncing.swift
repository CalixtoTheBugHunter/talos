import SwiftUI

/// How the console tells VoiceOver a line finished, apart from the concrete
/// system call so a test can inject a spy instead of asserting against a
/// real screen reader.
///
/// One call per finalized line, never one per chunk: "Streaming agent output
/// is announced without flooding — one announcement per meaningful unit of
/// output, never one per token."
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#voiceover
public protocol SessionConsoleAnnouncing: Sendable {
    func announce(_ text: String)
}

/// The live announcer: posts a system VoiceOver announcement.
public struct SystemVoiceOverAnnouncer: SessionConsoleAnnouncing {
    public init() {
        // Stateless — nothing to configure.
    }

    public func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}
