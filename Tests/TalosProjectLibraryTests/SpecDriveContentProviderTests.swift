import Foundation
@testable import TalosProjectLibrary
import Testing

/// Verifies the Spec Drive is reached through the provider interface rather than
/// against the provider directly, and that what the provider asks for is what
/// [decision 86](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions)
/// fixed: the wiki's Markdown, unaltered, written into `.talos/local/`.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#how-specs-are-retrieved
@Suite("Spec Drive content provider")
struct SpecDriveContentProviderTests {
    private static let wikiURL = "https://github.com/CalixtoTheBugHunter/talos/wiki"

    private static func root() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private static func location(
        _ url: String = wikiURL,
        syncRule: SpecDriveSyncRule = .readOnly
    ) -> SpecDriveLocation {
        SpecDriveLocation(provider: .githubWiki, url: url, syncRule: syncRule)
    }

    @Test("Every declared provider kind resolves to a provider that serves it")
    func everyKindResolves() {
        for kind in SpecDriveProviderKind.allCases {
            #expect(SpecDriveProviders.provider(for: kind).kind == kind)
        }
    }

    @Test("Fetched Markdown lands under .talos/local/, which is never committed")
    func destinationLivesUnderLocal() {
        let root = Self.root()
        let request = SpecDriveProviders
            .provider(for: .githubWiki)
            .fetchRequest(for: Self.location(), projectRoot: root)

        #expect(request.destination.path.hasPrefix(root.appendingPathComponent(".talos/local/spec-drive").path))
    }

    @Test("The same location resolves to the same directory every refresh, and two locations never collide")
    func destinationsAreStableAndDistinct() {
        let root = Self.root()
        let provider = GitHubWikiSpecDriveProvider()
        let first = provider.fetchRequest(for: Self.location(), projectRoot: root)
        let again = provider.fetchRequest(for: Self.location(), projectRoot: root)
        let other = provider.fetchRequest(for: Self.location("https://github.com/other/repo/wiki"), projectRoot: root)

        #expect(first.destination == again.destination)
        #expect(first.destination != other.destination)
    }

    @Test("The instruction names the wiki, the destination, and asks for the pages unaltered")
    func instructionNamesWikiAndDestination() {
        let root = Self.root()
        let request = GitHubWikiSpecDriveProvider().fetchRequest(for: Self.location(), projectRoot: root)

        #expect(request.instruction.contains(Self.wikiURL))
        #expect(request.instruction.contains(request.destination.path))
        #expect(request.instruction.contains("unaltered"))
        // The content is never asked for as the agent's answer — a model
        // reproducing a document retypes it, and the index would hold that.
        #expect(request.instruction.contains("Do not reproduce any page's contents in your reply"))
    }

    @Test("A declared-absent Spec Drive yields no fetch request, which is a state and not an error")
    func absentSpecDriveYieldsNoRequests() {
        #expect(SpecDriveProviders.fetchRequests(for: .absent, projectRoot: Self.root()).isEmpty)
    }

    @Test("Every declared location gets its own request, in declaration order")
    func oneRequestPerLocation() {
        let locations = [Self.location(), Self.location("https://github.com/other/repo/wiki")]
        let requests = SpecDriveProviders.fetchRequests(for: .locations(locations), projectRoot: Self.root())

        #expect(requests.map(\.location) == locations)
    }
}
