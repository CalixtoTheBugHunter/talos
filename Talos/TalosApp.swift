import SwiftUI
import TalosCore

/// The Talos app shell.
///
/// Deliberately empty: this target exists so the project builds, and the app
/// shell is its own board item. Liquid Glass is inherited from standard SwiftUI
/// chrome and never applied by hand, per
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Design-System#liquid-glass-is-inherited-never-applied
@main
struct TalosApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Placeholder content. Carries no values of its own — no palette, type scale,
/// or spacing grid exists to pick from:
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Design-System#the-platform-is-the-design-system
struct ContentView: View {
    var body: some View {
        // Without an explicit accessibility identity on the root view,
        // SwiftUI synthesizes an anonymous container at this position that
        // Apple's `performAccessibilityAudit()` flags as "Element has no
        // description" even though the Text itself already carries one.
        Text(verbatim: "Talos")
            .font(.largeTitle)
            .padding()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Talos")
    }
}
