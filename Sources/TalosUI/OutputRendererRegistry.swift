import SwiftUI

/// Resolves an ``OutputElementKind`` to the ``OutputRenderer`` that displays
/// it, degrading to ``PlainTextOutputRenderer`` for a kind nothing
/// registered. Lookup is kept separate from rendering so the dispatch itself
/// — not just its output — is what a caller can inspect and a test can
/// assert against.
public struct OutputRendererRegistry: Sendable {
    private var renderers: [OutputElementKind: any OutputRenderer] = [:]
    private let fallback: any OutputRenderer = PlainTextOutputRenderer()

    public init() {
        // Empty until something registers — no renderer is assumed.
    }

    /// The registry a console starts from: Markdown text registered as data,
    /// not as a case a caller has to know about.
    public static func withDefaults() -> Self {
        var registry = Self()
        registry.register(.markdown, renderer: MarkdownOutputRenderer())
        return registry
    }

    public mutating func register(_ kind: OutputElementKind, renderer: any OutputRenderer) {
        renderers[kind] = renderer
    }

    /// The renderer `kind` resolves to, or the plain-text fallback when
    /// nothing is registered for it.
    public func renderer(for kind: OutputElementKind) -> any OutputRenderer {
        renderers[kind] ?? fallback
    }

    public func view(for element: OutputElement) -> AnyView {
        renderer(for: element.kind).view(for: element)
    }
}
