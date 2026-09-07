import Foundation

/// Which hand-off Talos is performing — "opens your terminal app... at the
/// project path" or "opens the affected files in your preferred IDE".
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-you-use-instead
public enum ExternalAppRole: String, Equatable, Hashable, Sendable {
    case terminal
    case ide
}

/// One app Talos can hand off to for a given ``ExternalAppRole`` — a display
/// name and the bundle identifier `NSWorkspace` resolves it by.
public struct ExternalAppCandidate: Equatable, Hashable, Sendable {
    public let name: String
    public let bundleIdentifier: String

    public init(name: String, bundleIdentifier: String) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }
}

public extension ExternalAppCandidate {
    /// Named in this order because it is the order
    /// [Session Console](https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-you-use-instead)
    /// names them: "Terminal, iTerm, Ghostty".
    static let terminalCandidates: [ExternalAppCandidate] = [
        ExternalAppCandidate(name: "Terminal", bundleIdentifier: "com.apple.Terminal"),
        ExternalAppCandidate(name: "iTerm", bundleIdentifier: "com.googlecode.iterm2"),
        ExternalAppCandidate(name: "Ghostty", bundleIdentifier: "com.mitchellh.ghostty")
    ]

    /// "Talos never embeds a code editor... opens the affected files in the
    /// user's preferred IDE".
    static let ideCandidates: [ExternalAppCandidate] = [
        ExternalAppCandidate(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode"),
        ExternalAppCandidate(name: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode")
    ]

    /// The candidate list for `role`, in the order sensible detection
    /// checks them.
    static func candidates(for role: ExternalAppRole) -> [ExternalAppCandidate] {
        switch role {
        case .terminal: terminalCandidates
        case .ide: ideCandidates
        }
    }
}
