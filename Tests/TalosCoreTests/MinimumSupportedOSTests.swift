import Testing

@testable import TalosCore

/// Verifies the minimum OS the SPEC states.
///
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution
@Suite("Minimum supported OS")
struct MinimumSupportedOSTests {
    /// > | Minimum OS | macOS 26 |
    @Test("The SPEC's Minimum OS decision is macOS 26")
    func minimumOSIsMacOS26() {
        #expect(minimumSupportedMacOSMajorVersion == 26)
    }

    /// The package's own deployment target has to agree with the line above,
    /// otherwise the constant states one minimum while the build enforces
    /// another. `#unavailable` is false only when the target is macOS 26+.
    @Test("The build's deployment target is not below the stated minimum")
    func deploymentTargetMatchesTheStatedMinimum() {
        if #unavailable(macOS 26) {
            Issue.record("Deployment target is below the SPEC's macOS 26 minimum")
        }
    }
}
