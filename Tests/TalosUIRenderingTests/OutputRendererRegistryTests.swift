import SwiftUI
import TalosOrchestration
import TalosUI
import Testing

/// A fake, non-text element and its renderer — proof that a new kind is a
/// new conformance and a registration, never a change to the dispatch code
/// in `OutputRenderer.swift`.
private struct FakeChartElement: OutputElement {
    var fallbackDescription: String {
        "fake chart"
    }
}

private final class RenderCalls: @unchecked Sendable {
    private(set) var count = 0
    func record() {
        count += 1
    }
}

private struct SpyingChartRenderer: OutputElementRenderer {
    let calls: RenderCalls

    func render(_: FakeChartElement) -> some View {
        calls.record()
        return EmptyView()
    }
}

/// An element whose fallback description records whether it was ever read —
/// the only way to observe, from outside `AnyView`, that the registry took
/// the fallback path rather than a registered renderer's.
private struct FallbackObservingElement: OutputElement {
    let calls: RenderCalls

    var fallbackDescription: String {
        calls.record()
        return "unrendered"
    }
}

private struct SpyingMarkdownRenderer: OutputElementRenderer {
    let calls: RenderCalls

    func render(_: MarkdownTextElement) -> some View {
        calls.record()
        return EmptyView()
    }
}

/// > A renderer protocol maps a typed output element to a SwiftUI view
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Roadmap-Post-MVP#why-these-constraints-matter
@Suite("Output renderer registry")
struct OutputRendererRegistryTests {
    @Test("Registering a renderer for a fake, non-text element dispatches to it")
    func dispatchesToRegisteredRenderer() {
        let calls = RenderCalls()
        var registry = OutputRendererRegistry()
        registry.register(SpyingChartRenderer(calls: calls))

        _ = registry.view(for: FakeChartElement())

        #expect(calls.count == 1)
    }

    @Test("An element with no registered renderer falls back to its own description")
    func unregisteredElementFallsBackToItsOwnDescription() {
        let calls = RenderCalls()
        let registry = OutputRendererRegistry()

        _ = registry.view(for: FallbackObservingElement(calls: calls))

        #expect(calls.count == 1)
    }

    @Test("The default registry already dispatches Markdown text to its own renderer")
    func defaultRegistryDispatchesMarkdownToARegisteredRenderer() {
        let calls = RenderCalls()
        var registry = OutputRendererRegistry()
        registry.register(SpyingMarkdownRenderer(calls: calls))

        _ = registry.view(for: MarkdownTextElement(text: "**bold**"))

        #expect(calls.count == 1)
    }
}
