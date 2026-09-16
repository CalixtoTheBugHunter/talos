import SwiftUI

/// The persisted text-size factor and how the shell applies it.
///
/// Text size is one of the three things "restored across launch", and it is
/// held here as a factor persisted on change. Because it is `@AppStorage`, the
/// value survives quit and relaunch on its own — restoration is the storage,
/// not a separate load step.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#what-is-restored-across-launch
///
/// This type owns only the storage and the application seam. The **control**
/// that changes it — the View menu, `⌘+` / `⌘-` / `⌘0`, and the 100%–200% six
/// steps of decision 21 — is its own board item, and it writes this same key.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#text-size
public enum TextSizePreference {
    /// The `@AppStorage` / `UserDefaults` key the factor is stored under. The
    /// control that edits text size writes this key so its value is restored
    /// here.
    public static let storageKey = "talos.textSize.factor"

    /// 100% — the factor when nothing has been stored.
    public static let defaultFactor = 1.0

    /// 200% — the largest factor the control offers.
    public static let maximumFactor = 2.0

    /// The platform sizes the factor scales across, smallest to largest. The
    /// stored factor picks one by proportion, so the shell scales without any
    /// fixed point size of its own — "No fixed point sizes anywhere". The
    /// six-step control that edits the factor is refined with its own item.
    private static let scaledSizes: [DynamicTypeSize] = [
        .large, .xLarge, .xxLarge, .xxxLarge, .accessibility1, .accessibility2
    ]

    /// Maps the stored factor onto a platform `DynamicTypeSize`. macOS has no
    /// Dynamic Type control, so Talos drives this from its own factor, clamped
    /// to 100%–200% and spread evenly across the sizes above.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#text-size
    public static func dynamicTypeSize(forFactor factor: Double) -> DynamicTypeSize {
        let clamped = min(max(factor, defaultFactor), maximumFactor)
        let fraction = (clamped - defaultFactor) / (maximumFactor - defaultFactor)
        let lastIndex = scaledSizes.count - 1
        let index = Int((fraction * Double(lastIndex)).rounded())
        return scaledSizes[index]
    }
}

private struct TextSizePreferenceModifier: ViewModifier {
    @AppStorage(TextSizePreference.storageKey) private var factor = TextSizePreference.defaultFactor

    func body(content: Content) -> some View {
        content.dynamicTypeSize(TextSizePreference.dynamicTypeSize(forFactor: factor))
    }
}

public extension View {
    /// Applies the persisted, restored text-size factor to everything below it.
    /// Placed at the shell root so every surface inherits it.
    func talosTextSize() -> some View {
        modifier(TextSizePreferenceModifier())
    }
}
