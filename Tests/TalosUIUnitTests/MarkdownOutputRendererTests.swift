import Foundation
@testable import TalosUI
import Testing

/// Covers `MarkdownOutputRenderer`'s own parse-or-fallback decision.
/// `OutputRendererRegistryTests` exercises dispatch, not this: it never
/// renders real content through either branch.
@Suite("Markdown output renderer")
struct MarkdownOutputRendererTests {
    @Test("Real Markdown is parsed, not shown with its syntax characters")
    func parsesMarkdown() {
        let attributed = MarkdownOutputRenderer.attributedText(for: "**bold**")

        #expect(String(attributed.characters) == "bold")
    }

    @Test("A payload the parser rejects falls back to the exact original text")
    func fallsBackVerbatimOnParseFailure() {
        // `allowsExtendedAttributes` is off in `defaultOptions`; turned on
        // here only to reach an input Foundation's parser actually throws
        // on, since `defaultOptions` itself never does. The fallback logic
        // under test is the same either way.
        let throwingOptions = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        let payload = "^[text](attr:'unterminated)"

        let attributed = MarkdownOutputRenderer.attributedText(for: payload, options: throwingOptions)

        #expect(String(attributed.characters) == payload)
    }
}
