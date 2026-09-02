import SwiftUI

/// The visible Stop control — reachable at all times a session runs, never
/// behind a menu, a disclosure, or a confirmation.
///
/// Labeled "Stop session", not "Stop": sentence case for buttons is
/// specified with this exact phrase as the example.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice#writing-mechanics
///
/// > A stop button that needs confirming is not a stop button.
///
/// So this is a single tap: no `.confirmationDialog`, no second sheet, and
/// nothing armed differently from any other button. `.destructive` role is
/// the system's own semantic, not a hand-picked color — it degrades correctly
/// under Reduce Transparency and holds AA contrast in both appearance modes
/// the same way every other system-styled control does. See § The stop
/// guarantee is an interaction rule:
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard
struct SessionStopControlView: View {
    let onStop: () -> Void

    var body: some View {
        Button(role: .destructive, action: onStop) {
            Text(verbatim: "Stop session")
        }
        .accessibilityHint(Text(verbatim: "Ends the running session immediately. The agent process is killed."))
    }
}
