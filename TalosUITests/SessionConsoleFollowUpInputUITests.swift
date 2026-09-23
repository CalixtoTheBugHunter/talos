import XCTest

/// The Session Console's persistent input — "one input line for talking to the
/// agent" — checked against the accessibility gate: present whenever a session
/// is present, keyboard-reachable, VoiceOver-labeled, and always enabled so a
/// message can be sent at any time (what a message sent mid-turn does — interrupt
/// and supersede the running turn rather than run concurrently — is asserted at
/// `SessionFollowUpDecisionTests`). The transcript-seed launch environment key
/// mounts the real console before a live session exists.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility
final class SessionConsoleFollowUpInputUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// AC1 and AC5: the input is present, labeled for VoiceOver, always enabled,
    /// and its send affordance is reachable.
    @MainActor
    func testFollowUpInputIsLabeledAndAlwaysEnabled() {
        let app = launch(state: "resumable")
        let input = app.textFields["Message to the agent"]
        XCTAssertTrue(input.waitForExistence(timeout: 5), "the input is present whenever a session is present")
        XCTAssertTrue(input.isEnabled, "the input is always enabled, so a message can be sent at any time")
        XCTAssertTrue(app.buttons["Send"].waitForExistence(timeout: 5), "the send affordance is reachable and labeled")
    }

    @MainActor
    private func launch(state: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TALOS_UI_TEST_SESSION_CONSOLE_TRANSCRIPT"] = state
        app.launch()
        return app
    }
}
