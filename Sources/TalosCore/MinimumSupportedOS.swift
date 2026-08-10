/// The minimum OS Talos supports.
///
/// Declared in the SPEC, which the wiki owns:
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution
///
/// The `@available` attribute is what makes the minimum enforceable rather than
/// documented. `current` is a stored property of an unconditionally-available
/// type, so lowering the deployment target below macOS 26 fails the build here
/// instead of failing at runtime on a machine nobody tested.
@available(macOS 26, *)
public enum MinimumSupportedOS {
    /// The major version of the minimum macOS the SPEC requires.
    public static let majorVersion = 26
}

/// Forces the availability check above to be evaluated at every build.
///
/// Without a use outside an `@available` context, the attribute is inert: the
/// type simply goes unbuilt on a lower target and the build still succeeds.
public let minimumSupportedMacOSMajorVersion = MinimumSupportedOS.majorVersion
