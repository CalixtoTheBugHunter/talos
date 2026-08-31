import SwiftUI

/// Maps a typed ``OutputElement`` to the view that displays it. A conforming
/// type is registered under a kind rather than switching on one itself, so
/// adding a renderer is a registration and never a change to a caller.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Roadmap-Post-MVP#why-these-constraints-matter
public protocol OutputRenderer: Sendable {
    func view(for element: OutputElement) -> AnyView
}

/// The degrade path for a kind nothing is registered for: the element's own
/// payload, shown as-is rather than failing.
public struct PlainTextOutputRenderer: OutputRenderer {
    public init() {
        // Stateless — nothing to configure.
    }

    public func view(for element: OutputElement) -> AnyView {
        AnyView(Text(verbatim: element.payload).textSelection(.enabled))
    }
}
