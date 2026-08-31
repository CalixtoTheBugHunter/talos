import SwiftUI

/// Renders an ``OutputElement/kind`` of ``OutputElementKind/markdown`` — one
/// registered renderer among any number of others, not a hardcoded
/// assumption about agent output.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Roadmap-Post-MVP#why-these-constraints-matter
public struct MarkdownOutputRenderer: OutputRenderer {
    public init() {
        // Stateless — nothing to configure.
    }

    public func view(for element: OutputElement) -> AnyView {
        // `AttributedString(markdown:)`, not `Text(LocalizedStringKey:)`: the
        // payload is agent-produced text, not a localization key, and this
        // API is the one built to parse a dynamic string rather than a
        // source-literal one.
        guard let attributed = try? AttributedString(
            markdown: element.payload,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return AnyView(Text(verbatim: element.payload).textSelection(.enabled))
        }
        return AnyView(Text(attributed).textSelection(.enabled))
    }
}
