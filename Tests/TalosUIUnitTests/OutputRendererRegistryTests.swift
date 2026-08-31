import SwiftUI
import TalosUI
import Testing

/// Verifies the pluggable renderer interface:
///
/// > Output rendering must be a **pluggable renderer**, not hardcoded to
/// > Markdown text.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Roadmap-Post-MVP#why-these-constraints-matter
@Suite("Output renderer registry")
struct OutputRendererRegistryTests {
    /// Records the element it was asked to render, so a test can assert the
    /// registry actually invoked it rather than only resolving to it.
    final class SpyRenderer: OutputRenderer, @unchecked Sendable {
        private(set) var received: OutputElement?

        func view(for element: OutputElement) -> AnyView {
            received = element
            return AnyView(EmptyView())
        }
    }

    @Test("A fake renderer registered under its own kind is the one resolved")
    func registeredRendererResolves() {
        var registry = OutputRendererRegistry()
        let fakeKind = OutputElementKind(rawValue: "fake-chart")
        let spy = SpyRenderer()
        registry.register(fakeKind, renderer: spy)

        let resolved = registry.renderer(for: fakeKind)

        #expect(resolved is SpyRenderer)
    }

    @Test("The console's own dispatch invokes the registered renderer, with no branch on its kind")
    func dispatchInvokesTheRegisteredRenderer() {
        var registry = OutputRendererRegistry()
        let fakeKind = OutputElementKind(rawValue: "fake-chart")
        let spy = SpyRenderer()
        registry.register(fakeKind, renderer: spy)
        let element = OutputElement(kind: fakeKind, payload: "chart-data")

        _ = registry.view(for: element)

        #expect(spy.received == element)
    }

    @Test("An unregistered kind degrades to the plain-text renderer rather than failing")
    func unregisteredKindDegradesToPlainText() {
        let registry = OutputRendererRegistry()
        let unregistered = OutputElementKind(rawValue: "unregistered")

        let resolved = registry.renderer(for: unregistered)

        #expect(resolved is PlainTextOutputRenderer)
    }

    @Test("Markdown is registered data, not a hardcoded case")
    func defaultsRegisterMarkdown() {
        let registry = OutputRendererRegistry.withDefaults()

        let resolved = registry.renderer(for: .markdown)

        #expect(resolved is MarkdownOutputRenderer)
    }
}
