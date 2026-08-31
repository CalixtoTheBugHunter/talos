/// One typed piece of agent output ready to be shown, distinct from the raw
/// text an adapter streams. Markdown text is the only kind that ships now;
/// Visual Response adds more without this protocol, or anything that maps
/// over it, changing.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Roadmap-Post-MVP#why-these-constraints-matter
public protocol OutputElement: Sendable {
    /// Shown when no renderer is registered for this element's own type — the
    /// reason a lookup can answer for every element rather than failing when
    /// a new kind ships before its renderer does.
    var fallbackDescription: String { get }
}

/// The one ``OutputElement`` Talos ships at MVP: an agent's output, rendered
/// as Markdown rather than assumed to be plain text.
public struct MarkdownTextElement: OutputElement, Equatable {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public var fallbackDescription: String {
        text
    }
}
