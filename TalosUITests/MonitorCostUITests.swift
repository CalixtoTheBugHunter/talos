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
