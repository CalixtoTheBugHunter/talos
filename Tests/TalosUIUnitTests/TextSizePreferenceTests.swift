import SwiftUI
import TalosUI
import Testing

/// Verifies ``TextSizePreference/dynamicTypeSize(forFactor:)`` against
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#text-size
/// — the stored factor scales across the platform sizes, clamped to the
/// 100%–200% range decision 21 fixes, so the 200% layout the gate requires is
/// what the largest factor produces.
@Suite("Text size preference")
struct TextSizePreferenceTests {
    @Test("100% maps to the base size and 200% to the largest")
    func endpointsMapToBaseAndLargest() {
        #expect(TextSizePreference.dynamicTypeSize(forFactor: 1.0) == .large)
        #expect(TextSizePreference.dynamicTypeSize(forFactor: 2.0) == .accessibility2)
    }

    @Test("Factors outside 100%–200% are clamped, not extrapolated")
    func outOfRangeFactorsAreClamped() {
        #expect(TextSizePreference.dynamicTypeSize(forFactor: 0.5) == .large)
        #expect(TextSizePreference.dynamicTypeSize(forFactor: 3.0) == .accessibility2)
    }

    @Test("A mid-range factor lands on an intermediate size, never below base")
    func midRangeFactorScalesUpward() {
        let mid = TextSizePreference.dynamicTypeSize(forFactor: 1.5)
        #expect(mid > .large)
        #expect(mid < .accessibility2)
    }
}
