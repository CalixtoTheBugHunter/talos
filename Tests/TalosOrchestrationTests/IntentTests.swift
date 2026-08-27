@testable import TalosOrchestration
import TalosProjectLibrary
import Testing

/// Verifies ``Intent`` carries what the shared session pipeline needs without
/// coupling to typed text, per
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Roadmap-Post-MVP#why-these-constraints-matter.
///
/// `Intent` is the only declaration in `TalosOrchestration` today, and it
/// takes no `String` parameter of its own — the "no pipeline stage takes a
/// bare `String`" criterion has nothing else in this module to check yet.
@Suite("Intent")
struct IntentTests {
    @Test("A scheduler-sourced intent is constructible without any typed text")
    func schedulerSourcedIntentIsConstructible() {
        let intent = Intent(
            content: "Run the nightly guideline review.",
            source: .scheduler,
            project: .generate(),
            requestingSubFunction: .advisor
        )

        #expect(intent.source == .scheduler)
        #expect(intent.requestingSubFunction == .advisor)
    }

    @Test("A user-text intent carries the same four fields")
    func userTextIntentCarriesItsFields() {
        let project = ProjectIdentifier.generate()
        let intent = Intent(
            content: "Add a dark mode toggle.",
            source: .userText,
            project: project,
            requestingSubFunction: .assistant
        )

        #expect(intent.content == "Add a dark mode toggle.")
        #expect(intent.source == .userText)
        #expect(intent.project == project)
        #expect(intent.requestingSubFunction == .assistant)
    }
}
