@testable import TalosCore
import Testing

@Suite("ExternalAppResolver")
struct ExternalAppResolverTests {
    private let terminal = ExternalAppCandidate(name: "Terminal", bundleIdentifier: "com.apple.Terminal")
    private let iTerm = ExternalAppCandidate(name: "iTerm", bundleIdentifier: "com.googlecode.iterm2")

    @Test("A configured, installed app resolves to itself")
    func configuredAndInstalledResolves() {
        let resolver = ExternalAppResolver(isInstalled: { $0 == iTerm.bundleIdentifier })
        let resolution = resolver.resolve(role: .terminal, configured: iTerm, candidates: [terminal, iTerm])
        #expect(resolution == .resolved(iTerm))
    }

    @Test("A configured but no-longer-installed app is missing, never a silent fallback to another candidate")
    func configuredButNotInstalledIsMissingNotFallback() {
        let resolver = ExternalAppResolver(isInstalled: { $0 == terminal.bundleIdentifier })
        let resolution = resolver.resolve(role: .terminal, configured: iTerm, candidates: [terminal, iTerm])
        #expect(resolution == .missing)
    }

    @Test("With no configured app, the first installed candidate is auto-detected")
    func unconfiguredAutoDetectsFirstInstalled() {
        let resolver = ExternalAppResolver(isInstalled: { $0 == iTerm.bundleIdentifier })
        let resolution = resolver.resolve(role: .terminal, configured: nil, candidates: [terminal, iTerm])
        #expect(resolution == .resolved(iTerm))
    }

    @Test("With no configured app and none installed, resolution is missing")
    func unconfiguredWithNoneInstalledIsMissing() {
        let resolver = ExternalAppResolver(isInstalled: { _ in false })
        let resolution = resolver.resolve(role: .terminal, configured: nil, candidates: [terminal, iTerm])
        #expect(resolution == .missing)
    }

    @Test("The default candidate lists are used when none are passed explicitly")
    func defaultCandidatesAreUsedWhenNoneGiven() {
        let resolver = ExternalAppResolver(isInstalled: { $0 == "com.apple.dt.Xcode" })
        let resolution = resolver.resolve(role: .ide, configured: nil)
        #expect(resolution == .resolved(ExternalAppCandidate(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")))
    }
}
