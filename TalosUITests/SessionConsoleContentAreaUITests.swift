import XCTest

/// The Session Console renders in the main window's content area, not a modal
/// sheet, built on
/// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#every-surface-placed
/// ("the selected session opens in the content area as the Session Console").
final class SessionConsoleContentAreaUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// AC1 and AC3: a session renders in the content area, and no modal sheet
    /// presents it — the transcript is on screen and `app.sheets` is empty.
    @MainActor
    func testSessionRendersInTheContentAreaAndNotASheet() {
        let app = launch(state: "failed")
        XCTAssertTrue(
            app.staticTexts["Found 3 matches."].waitForExistence(timeout: 5),
            "the transcript is on screen in the content area"
        )
        XCTAssertEqual(app.sheets.count, 0, "the session is in the content area, never a modal sheet")
    }

    /// AC4: while a session runs with its console in the content area, the
    /// always-visible Stop control is reachable and not occluded — the case the
    /// sheet used to break, which is why the sheet hosted its own Stop. Here the
    /// app-hosted control shows over the console.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#stop-stays-reachable
    @MainActor
    func testStopIsReachableWhileTheConsoleRunsInTheContentArea() {
        let app = launch(state: "loading")
        XCTAssertTrue(
            app.staticTexts["Waiting for the agent to respond."].waitForExistence(timeout: 5),
            "the running console is on screen in the content area"
        )
        let stop = app.buttons["Stop session"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5), "the Stop control is reachable over the content-area console")
        XCTAssertTrue(stop.isHittable, "the Stop control is not occluded by the console")
    }

    /// "A running session's indicator stays visible whichever surface is
    /// shown" — a session running behind a surface the user navigated away
    /// from is the case that tests it, so navigate off Sessions and assert the
    /// app-scoped Stop control persists.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/App-Shell-and-Navigation#stop-stays-reachable
    @MainActor
    func testStopStaysReachableAfterNavigatingToAnotherSurface() {
        let app = launch(state: "loading")
        let stop = app.buttons["Stop session"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5), "the Stop control shows while the session runs")

        app.staticTexts["Monitor"].click()
        XCTAssertTrue(
            app.staticTexts["This surface is not available yet."].waitForExistence(timeout: 5),
            "the sidebar actually switched to another surface"
        )

        XCTAssertTrue(stop.waitForExistence(timeout: 5), "the Stop control stays visible on the other surface")
        XCTAssertTrue(stop.isHittable, "and stays reachable there, not occluded by the surface switch")
    }

    /// The Stop control ends the running session with no confirmation in the
    /// way: activating it publishes the session as no longer running, so the
    /// always-visible control drops.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
    @MainActor
    func testStopControlEndsTheRunningConsoleSession() {
        let app = launch(state: "loading")
        let stop = app.buttons["Stop session"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))

        stop.click()

        XCTAssertFalse(stop.waitForExistence(timeout: 5), "stopping ends the session with no confirmation in the way")
    }

    /// AC1's "start a session after closing the old one": once a session has
    /// ended, closing the console returns the start form to the content area
    /// rather than leaving a dead transcript in the way.
    @MainActor
    func testClosingAnEndedConsoleReturnsTheStartForm() {
        let app = launch(state: "denied")
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "an ended session offers a Close control")

        close.click()

        XCTAssertTrue(
            app.buttons["Start Assistant Session"].waitForExistence(timeout: 5),
            "closing returns the start form so another session can begin"
        )
        XCTAssertFalse(
            app.staticTexts["Denied. Session ended, nothing further ran."].exists,
            "the ended transcript is gone once the console is closed"
        )
    }

    @MainActor
    private func launch(state: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TALOS_UI_TEST_SESSION_CONSOLE_TRANSCRIPT"] = state
        app.launch()
        return app
    }
}
