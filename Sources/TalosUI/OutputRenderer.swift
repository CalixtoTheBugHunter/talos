import SwiftUI
import TalosOrchestration

/// Maps one ``OutputElement`` type to the SwiftUI view that shows it. A new
/// renderer is a new conformance, registered with ``OutputRendererRegistry``
/// — nothing that already renders is touched.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Roadmap-Post-MVP#why-these-constraints-matter
public protocol OutputElementRenderer: Sendable {
    associatedtype Element: OutputElement
    associatedtype Body: View

    @ViewBuilder
    func render(_ element: Element) -> Body
}

/// The renderer for ``MarkdownTextElement`` — registered like any other, not
/// a case the dispatch below special-cases.
public struct MarkdownTextRenderer: OutputElementRenderer {
    public init() {
        // No state to hold: rendering is a pure function of the element.
    }

    /// Renders `element.text` as Markdown, falling back to it verbatim if it
    /// fails to parse.
    public func render(_ element: MarkdownTextElement) -> some View {
        if let markdown = try? AttributedString(markdown: element.text) {
            Text(markdown)
        } else {
            Text(element.text)
        }
    }
}

/// Resolves an ``OutputElement``'s concrete type to the renderer registered
/// for it, keyed by type rather than by name: an element kind is a Swift
/// type nobody hand-writes a config string for, unlike an adapter name in
/// `agents.yaml`.
///
/// An element with no registered renderer falls back to its own
/// ``OutputElement/fallbackDescription`` shown as plain text, rather than
/// failing — the same reason a lookup here can never throw.
public struct OutputRendererRegistry {
    private var renderers: [ObjectIdentifier: (any OutputElement) -> AnyView] = [:]

    /// A registry with `MarkdownTextRenderer` already registered — the one
    /// renderer Talos ships, registered the same way any other one would be.
    public init() {
        register(MarkdownTextRenderer())
    }

    /// Registers `renderer` for its `Element` type, replacing any renderer
    /// already registered for that type.
    public mutating func register<Renderer: OutputElementRenderer>(_ renderer: Renderer) {
        let key = ObjectIdentifier(Renderer.Element.self)
        renderers[key] = { element in
            guard let typed = element as? Renderer.Element else {
                return AnyView(Text(element.fallbackDescription))
            }
            return AnyView(renderer.render(typed))
        }
    }

    /// The view for `element`: its registered renderer's, or its fallback
    /// description as plain text when none is registered.
    public func view(for element: any OutputElement) -> AnyView {
        let key = ObjectIdentifier(type(of: element))
        guard let render = renderers[key] else {
            return AnyView(Text(element.fallbackDescription))
        }
        return render(element)
    }
}

/// The seam the future session console mounts unchanged: it dispatches to
/// whatever ``OutputRendererRegistry`` resolves, with no branch of its own on
/// any element's kind.
public struct OutputElementView: View {
    private let element: any OutputElement
    private let registry: OutputRendererRegistry

    public init(element: any OutputElement, registry: OutputRendererRegistry) {
        self.element = element
        self.registry = registry
    }

    public var body: some View {
        registry.view(for: element)
    }
}
