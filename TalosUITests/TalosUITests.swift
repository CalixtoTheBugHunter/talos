import XCTest

/// The `a11y` CI stage's structural audit, per
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Verification
///
/// > `a11y` asserts labels, hints, and roles. Whether the *spoken result* is
/// > comprehensible is a judgement...
///
/// `performAccessibilityAudit()` is Apple's own structural audit — labels,
/// traits, contrast, hit-target size — and is what this stage claims. It
/// does not claim comprehensibility, streaming-output announcements, the
/// approval prompt, or coverage of surfaces that do not exist yet; that
/// deeper audit is https://github.com/CalixtoTheBugHunter/talos/issues/97,
/// which grows this file surface by surface as they are built.
final class TalosUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRootWindowHasNoAccessibilityAuditIssues() throws {
        let app = XCUIApplication()
        app.launch()
        try app.performAccessibilityAudit { issue in
            print("ACCESSIBILITY AUDIT ISSUE: \(issue)")
            print("  element: \(issue.element?.debugDescription ?? "nil")")
            print("  auditType: \(issue.auditType)")
            print("  compactDescription: \(issue.compactDescription)")
            return false
        }
    }
}
