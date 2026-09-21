import Foundation

/// The board-state fetch: Talos renders the request and reads the JSON that
/// lands; the connected agent reads the board with its own MCP/CLI and writes
/// the items. Talos holds no board client, per
/// [decision 93](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions).
public struct BoardStateFetchRequest: Equatable, Sendable {
    /// The file the agent writes the board items into, as a JSON array of
    /// `{id, title, column}`.
    public let destination: URL
    public let instruction: String

    public init(destination: URL, instruction: String) {
        self.destination = destination
        self.instruction = instruction
    }
}

/// Builds the one board-state fetch request for a project's declared board. A
/// project with no board has nothing to fetch, so the caller renders a labeled
/// absence rather than running anything.
public enum BoardStateFetch {
    /// The request that reads `board` into the project at `projectRoot`.
    public static func fetchRequest(for board: BoardManifest, projectRoot: URL) -> BoardStateFetchRequest {
        let destination = BoardStateLayout.itemsFile(projectRoot: projectRoot)
        return BoardStateFetchRequest(
            destination: destination,
            instruction: instruction(provider: board.provider, destination: destination)
        )
    }

    /// Names the destination and the exact JSON shape, and forbids writing
    /// elsewhere: every write this run makes crosses the Safeguards gate, and
    /// the shape is fixed so the agent maps its provider onto the canonical
    /// `{id, title, column}` and no provider-specific field reaches Talos.
    /// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions
    private static func instruction(provider: BoardProviderKind, destination: URL) -> String {
        """
        Read this project's board so Talos can assemble its state into context.

        The board provider is \(provider.rawValue). Using your own tools, read every board item and \
        write them as a single JSON array to this file, creating its directory if needed:

        \(destination.path)

        Each element is an object with these string fields: "id" (the provider's stable item \
        identifier), "title" (the item's title), and "column" (the provider's own column or status \
        name, unchanged — do not map it onto any other value). Where the provider exposes them, also \
        include "updatedBy" (who last changed the item), "updatedAt" (when it last changed, as the \
        provider states it), and "url" (the item's page on the provider); omit any of these the \
        provider does not supply. Write valid JSON and \
        nothing else into that file, write nothing outside it, and change nothing on the board. Do not \
        reproduce the items in your reply — Talos reads the file. Reply with how many items you wrote.
        """
    }
}

/// Where fetched board state lands — under `local/`, gitignored and discardable
/// like the board state assembled from it.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives
public enum BoardStateLayout {
    /// The directory the board fetch writes into.
    public static func root(projectRoot: URL) -> URL {
        projectRoot.appendingPathComponent(".talos/local/board", isDirectory: true)
    }

    /// The single JSON file holding the fetched items.
    public static func itemsFile(projectRoot: URL) -> URL {
        root(projectRoot: projectRoot).appendingPathComponent("items.json", isDirectory: false)
    }
}
