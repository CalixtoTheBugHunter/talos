import SwiftUI

/// The menu commands behind ``OpenInTerminalCommand`` and
/// ``OpenInIDECommand`` — "Talos opens your terminal app... at the project
/// path" and "Talos opens the affected files in your preferred IDE". A
/// separate `Commands` conformance, rather than inline in `TalosApp`, for
/// the same reason `LogExportCommand` and `SessionTranscriptExportCommand`
/// are free-standing types: `App` is a value type SwiftUI recreates.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-you-use-instead
struct HandOffCommands: Commands {
    var body: some Commands {
        CommandMenu("Hand Off") {
            Button("Open Terminal Here…") {
                OpenInTerminalCommand.run()
            }
            Button("Open in IDE…") {
                OpenInIDECommand.run()
            }
            Divider()
            Button("Choose Terminal App…") {
                OpenInTerminalCommand.chooseApp()
            }
            Button("Choose IDE…") {
                OpenInIDECommand.chooseApp()
            }
        }
    }
}
