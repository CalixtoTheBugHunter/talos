import Foundation

/// One declared location's fetch: Talos renders the request and reads the
/// files that land; the agent fetches. The content is never the agent's answer
/// — a model reproducing a document retypes it.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions
public struct SpecDriveFetchRequest: Equatable, Sendable {
    public let location: SpecDriveLocation
    /// The directory the agent writes the location's `.md` files into.
    public let destination: URL
    public let instruction: String

    public init(location: SpecDriveLocation, destination: URL, instruction: String) {
        self.location = location
        self.destination = destination
        self.instruction = instruction
    }
}

/// How one kind of Spec Drive is fetched. Callers hold the protocol, so a
/// second provider is a new conformance rather than a branch at every call
/// site — per [decision 36](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions).
public protocol SpecDriveContentProvider: Sendable {
    /// The `spec.yaml` provider this conformance serves.
    var kind: SpecDriveProviderKind { get }
    /// The fetch request for `location` in the project at `projectRoot`.
    func fetchRequest(for location: SpecDriveLocation, projectRoot: URL) -> SpecDriveFetchRequest
}

/// Resolves the provider for a declared location, total over
/// ``SpecDriveProviderKind`` so adding a kind is a compile error, not a runtime nil.
public enum SpecDriveProviders {
    /// The provider serving `kind`, returned as the protocol.
    public static func provider(for kind: SpecDriveProviderKind) -> any SpecDriveContentProvider {
        switch kind {
        case .githubWiki: GitHubWikiSpecDriveProvider()
        }
    }

    /// One request per declared location; empty for a declared-absent Spec
    /// Drive, which is a state rather than an error.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#when-a-project-has-no-spec-drive
    public static func fetchRequests(for specDrive: SpecDrive, projectRoot: URL) -> [SpecDriveFetchRequest] {
        switch specDrive {
        case .absent:
            []
        case let .locations(locations):
            locations.map { provider(for: $0.provider).fetchRequest(for: $0, projectRoot: projectRoot) }
        }
    }
}

/// The only Spec Drive provider at MVP. A GitHub Wiki is a git repository, so
/// the agent already has a way to read one with its own tools and Talos needs
/// no client of its own.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#spec-drive
public struct GitHubWikiSpecDriveProvider: SpecDriveContentProvider {
    public let kind = SpecDriveProviderKind.githubWiki

    public init() {
        // Stateless.
    }

    public func fetchRequest(for location: SpecDriveLocation, projectRoot: URL) -> SpecDriveFetchRequest {
        let destination = SpecDriveFetchLayout.destination(projectRoot: projectRoot, locationURL: location.url)
        return SpecDriveFetchRequest(
            location: location,
            destination: destination,
            instruction: instruction(url: location.url, destination: destination)
        )
    }

    /// Names the destination and forbids writing elsewhere, because every write
    /// this run makes crosses the Safeguards gate and a request the user has to
    /// approve should say exactly what it touches.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules
    private func instruction(url: String, destination: URL) -> String {
        """
        Fetch this project's Spec Drive so Talos can index it.

        The Spec Drive is the GitHub Wiki at \(url). Using your own tools — the wiki is a git \
        repository at \(url).git, so cloning it is usually enough — write every wiki page as one \
        Markdown file into this directory, creating it if needed:

        \(destination.path)

        Write the pages unaltered: no summarizing, reformatting, renaming, or editing, and keep the \
        `.md` extension each page already has. Write nothing outside that directory, and change \
        nothing in the wiki. Do not reproduce any page's contents in your reply — Talos reads the \
        files. Reply with how many Markdown files you wrote.
        """
    }
}

/// Where fetched Spec Drive Markdown lands — under `local/`, gitignored and
/// discardable like the index built from it.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives
public enum SpecDriveFetchLayout {
    /// The root every location's directory sits under.
    public static func root(projectRoot: URL) -> URL {
        projectRoot.appendingPathComponent(".talos/local/spec-drive", isDirectory: true)
    }

    /// One directory per location, named from its URL so the same declaration
    /// always resolves to the same directory and two locations never collide.
    public static func destination(projectRoot: URL, locationURL: String) -> URL {
        root(projectRoot: projectRoot).appendingPathComponent(slug(for: locationURL), isDirectory: true)
    }

    /// A filesystem-safe, stable name: alphanumerics kept, every other run
    /// collapsed to a single `-`.
    static func slug(for locationURL: String) -> String {
        let scrubbed = locationURL.lowercased().map { character in
            character.isLetter || character.isNumber ? character : "-"
        }
        let name = String(scrubbed)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return name.isEmpty ? "location" : name
    }
}
