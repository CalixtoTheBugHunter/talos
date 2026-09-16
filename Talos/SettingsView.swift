import SwiftUI

/// The `Settings` scene's content, reached at `⌘,`. The scene is part of the
/// window model this shell establishes; its controls — light/dark appearance
/// and the text-size control of decision 21 — are their own board item, so
/// this is a placeholder until then.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#one-window
struct SettingsView: View {
    var body: some View {
        Form {
            Text("Settings will appear here.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
