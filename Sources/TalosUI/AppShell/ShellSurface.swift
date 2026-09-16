import SwiftUI

/// The top-level surfaces the sidebar navigates between, in sidebar order.
///
/// The order of the cases *is* the cycle order: `⌘⌥→` / `⌘⌥←` moves to the
/// next and previous case, wrapping at each end, because "Sidebar order is the
/// cycle order" and focus order follows reading order.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#moving-between-surfaces
///
/// The four sub-functions are deliberately absent: they "are not top-level
/// surfaces" and are selected inside a session rather than navigated to.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#every-surface-placed
public enum ShellSurface: String, CaseIterable, Identifiable, Hashable, Sendable {
    case sessions
    case monitor
    case chatHistory
    case localMemories
    case projectLibrary

    public var id: String {
        rawValue
    }

    /// Sidebar and View-menu label. A plain noun; Talos words its own copy and
    /// never says "I".
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice
    public var title: String {
        switch self {
        case .sessions: "Sessions"
        case .monitor: "Monitor"
        case .chatHistory: "Chat History"
        case .localMemories: "Local Memories"
        case .projectLibrary: "Project Library"
        }
    }

    /// An SF Symbol, never a custom icon set — Talos adopts the platform's.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Design-System#the-platform-is-the-design-system
    public var systemImage: String {
        switch self {
        case .sessions: "bubble.left.and.text.bubble.right"
        case .monitor: "chart.bar"
        case .chatHistory: "clock.arrow.circlepath"
        case .localMemories: "brain"
        case .projectLibrary: "books.vertical"
        }
    }

    /// The next surface in sidebar order, wrapping from the last back to the
    /// first — the forward half of `⌘⌥→`.
    public var next: Self {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? all.startIndex
        return all[(index + 1) % all.count]
    }

    /// The previous surface in sidebar order, wrapping from the first back to
    /// the last — the backward half of `⌘⌥←`.
    public var previous: Self {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? all.startIndex
        return all[(index - 1 + all.count) % all.count]
    }
}
