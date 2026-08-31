import SwiftUI

/// Renders an ``OutputElement/kind`` of ``OutputElementKind/markdown`` — one
/// registered renderer among any number of others, not a hardcoded
/// assumption about agent output.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Roadmap-Post-MVP#why-these-constraints-matter
public struct MarkdownOutputRenderer: OutputRenderer {
    static let defaultOptions = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace
    )

    public init() {
        // Stateless — nothing to configure.
    }

    public func view(for element: OutputElement) -> AnyView {
        AnyView(Text(Self.attributedText(for: element.payload)).textSelection(.enabled))
    }

    /// The parse-or-fallback decision, apart from the `View` it ends up in so
    /// a test can assert on the value rather than on an opaque `AnyView`.
    /// `options` defaults to what `view(for:)` actually uses; a test overrides
    /// it only to drive the fallback branch deterministically.
    ///
    /// `AttributedString(markdown:)`, not `Text(LocalizedStringKey:)`: the
    /// payload is agent-produced text, not a localization key, and this API
    /// is the one built to parse a dynamic string rather than a
    /// source-literal one.
    static func attributedText(
        for payload: String,
        options: AttributedString.MarkdownParsingOptions = defaultOptions
    ) -> AttributedString {
        (try? AttributedString(markdown: payload, options: options)) ?? AttributedString(payload)
    }
}
