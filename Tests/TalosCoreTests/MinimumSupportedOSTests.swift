import Testing

@testable import TalosCore

/// Verifies the minimum OS the SPEC states.
///
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution
@Suite("Minimum supported OS")
struct MinimumSupportedOSTests {
    /// > | Minimum OS | macOS 26 |
    ///
    /// This asserts the stated minimum and nothing more: it fails when
    /// `majorVersion` drifts off the SPEC's number, verified by setting it to 15
    /// and watching this test fail.
    ///
    /// The **deployment target** is not checked here, because no runtime
    /// assertion can check it. A `#unavailable(macOS 26)` check reads the OS
    /// running the suite — macOS 26 or newer on any machine able to run it — so
    /// it passes against a regressed target as readily as a correct one.
    ///
    /// What enforces the target is `MinimumSupportedOS` being
    /// `@available(macOS 26, *)` and used unconditionally in
    /// `minimumSupportedMacOSMajorVersion`: lowering the target below macOS 26
    /// fails compilation of the package, verified with
    /// `platforms: [.macOS(.v15)]` and with
    /// `MACOSX_DEPLOYMENT_TARGET=15.0` against the app target. That is a
    /// build-time guarantee, and a test that appeared to re-check it would only
    /// obscure where the real enforcement lives.
    @Test("The SPEC's Minimum OS decision is macOS 26")
    func minimumOSIsMacOS26() {
        #expect(MinimumSupportedOS.majorVersion == 26)
    }
}
