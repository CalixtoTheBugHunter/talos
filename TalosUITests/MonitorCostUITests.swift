import XCTest

/// The Monitor's cost surface, driven through the real, mounted view with a
/// seeded set of sessions: every cost figure is labeled an estimate (a priced
/// session, and two the table cannot price, shown as unavailable rather than
/// `$0`), and the shipped price table's date is visible so the user knows how
/// current the estimate's basis is.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice#cost-copy
final class MonitorCostUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMonitorCostListLabelsEveryFigureAnEstimateAndShowsThePriceDate() {
        let app = launchWithMonitorCost()

        XCTAssertTrue(
            text(containing: "Prices as of", in: app).waitForExistence(timeout: 5),
            "the price table's effective date is shown"
        )
        XCTAssertTrue(
            text(containing: "not a bill", in: app).exists,
            "the surface states the figures are estimates, not a bill"
        )

        XCTAssertTrue(
            text(containing: "Estimated cost: ", in: app).waitForExistence(timeout: 5),
            "a priced session's cost is labeled an estimate"
        )
        XCTAssertTrue(
            text(containing: "Estimated cost unavailable — no price for experimental-model-x", in: app).exists,
            "an unknown model reports cost unavailable, never a guessed figure"
        )
        XCTAssertTrue(
            text(containing: "Estimated cost unavailable — session log format not recognized", in: app).exists,
            "an unparsable token report reports cost unavailable, not a zero"
        )

        // Talos-added token overhead:
        // https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-token-overhead-is-computed
        XCTAssertTrue(
            text(containing: "Estimated Talos-added token overhead: ", in: app).exists,
            "overhead is shown per session and as an aggregate, labeled an estimate"
        )
        XCTAssertTrue(
            text(containing: "Computed from 2 sessions; 4 excluded", in: app).exists,
            "the aggregate states how many sessions it covers and how many were excluded"
        )
        XCTAssertTrue(
            text(containing: "Over the 5% token-overhead budget", in: app).exists,
            "exceeding 5% is flagged in words, not by colour"
        )
    }

    /// Duration, outcome, and the success rate with its exclusions are shown for
    /// every session run, and the chart states what it plots in words.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-task-outcome-is-classified
    @MainActor
    func testMonitorShowsDurationOutcomeSuccessRateAndChartSummary() {
        let app = launchWithMonitorCost()
        XCTAssertTrue(
            text(containing: "Success rate: 75% (3 of 4 rated sessions exited cleanly)", in: app)
                .waitForExistence(timeout: 5),
            "the rate is Succeeded over Succeeded + Failed"
        )
        XCTAssertTrue(
            text(containing: "2 excluded from the rate: 1 denied, 1 stopped.", in: app).exists,
            "Denied and Stopped are excluded and counted, never silently"
        )
        XCTAssertTrue(
            text(containing: "Duration: 2 min 5 s, excluding time awaiting a decision", in: app).exists,
            "duration is shown and says it excludes the decision wait"
        )
        XCTAssertTrue(
            text(containing: "Outcome: Denied — recorded as denied, not as an error", in: app).exists,
            "a denial is recorded as denied, not as an error"
        )
        let chartSummary = "Tokens per session: 2 sessions plotted; 4 not plotted (no token count)."
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", chartSummary)).firstMatch.exists,
            "the chart carries its reading as a label, including what it did not plot"
        )
    }

    /// Choosing a sub-function narrows the sessions and the rate together —
    /// reached, opened, and chosen with the keyboard alone, no pointer event.
    /// Needs Full Keyboard Access on, which the `a11y` job turns on: Tab skips
    /// popups without it, and a launch argument cannot enable it.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#no-mouse-only-paths
    @MainActor
    func testSubFunctionFilterNarrowsSessionsAndRateByKeyboardAlone() {
        let app = launchWithMonitorCost()
        let picker = app.popUpButtons["Sub-function"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "the sub-function filter is a labeled control")
        var tabs = 0
        while !hasKeyboardFocus(picker), tabs < Self.maximumTabs {
            app.typeKey(.tab, modifierFlags: [])
            tabs += 1
        }
        XCTAssertTrue(hasKeyboardFocus(picker), "Tab reaches the sub-function filter")
        app.typeKey(.space, modifierFlags: [])
        app.typeText("Automator\r")

        XCTAssertTrue(
            text(containing: "Success rate: 100% (1 of 1 rated session exited cleanly)", in: app)
                .waitForExistence(timeout: 5),
            "the rate is recomputed over the filtered sessions"
        )
        XCTAssertFalse(
            text(containing: "experimental-model-x", in: app).exists,
            "an Assistant session is no longer listed"
        )
    }

    @MainActor
    func testMonitorCostSurfacePassesAccessibilityAuditWhilePresented() throws {
        let app = launchWithMonitorCost()
        XCTAssertTrue(text(containing: "Prices as of", in: app).waitForExistence(timeout: 5))
        try assertNoTalosOwnAccessibilityIssues(on: app)
    }

    @MainActor
    private func launchWithMonitorCost() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TALOS_UI_TEST_MONITOR_COST"] = "1"
        app.launch()
        return app
    }

    private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) == true
    }

    private static let maximumTabs = 20

    /// SwiftUI text surfaces its string in the element's `value` on this
    /// platform (a combined cost row included, as one static text carrying the
    /// whole line), with an empty `label` — so match a substring of either.
    @MainActor
    private func text(containing substring: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", substring, substring)
        ).firstMatch
    }

    /// The surface's own elements pass Apple's structural accessibility audit,
    /// filtered to Talos-authored element types the way the main suite does.
    @MainActor
    private func assertNoTalosOwnAccessibilityIssues(on app: XCUIApplication) throws {
        var talosOwnIssues: [XCUIAccessibilityAuditIssue] = []
        // `.contrast` is dropped for the same reason as the main suite: the
        // gate verifies contrast by inheritance and `lint`, not this audit.
        try app.performAccessibilityAudit(for: .all.subtracting(.contrast)) { issue in
            guard let elementType = issue.element?.elementType,
                  elementType == .staticText || elementType == .button
            else {
                return true
            }
            talosOwnIssues.append(issue)
            return true
        }

        for issue in talosOwnIssues {
            print("ACCESSIBILITY AUDIT ISSUE: \(issue)")
        }
        print("ACCESSIBILITY_ISSUE_COUNT: \(talosOwnIssues.count)")
        XCTAssertTrue(talosOwnIssues.isEmpty, "\(talosOwnIssues.count) accessibility issue(s) on Talos's own elements")
    }
}
