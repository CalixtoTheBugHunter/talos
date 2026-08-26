import Foundation

// Resolving an adapter by the name a user wrote in `.talos/agents.yaml`.
// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#ai-agent
// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives

/// Thrown when no adapter is registered under a name. Names the file, the
/// value, and the fix, because the name came from a file a user wrote by
/// hand.
public struct UnknownAdapterError: Error, Equatable, Sendable {
    /// The `adapter:` value that resolved to nothing.
    public let name: String
    /// The names that would have resolved, sorted, so the message can list
    /// them.
    public let registeredNames: [String]
    /// What to change to fix it, stated as an instruction.
    public let fix: String

    public init(name: String, registeredNames: [String]) {
        self.name = name
        self.registeredNames = registeredNames.sorted()
        // With nothing registered there is no list to choose from, and
        // "one of: ." is a fix naming no fix. The remedy is a different one,
        // so it is stated instead of interpolated into an empty sentence.
        if self.registeredNames.isEmpty {
            fix = "No adapter named '\(name)' is registered, and no adapter is registered at all. " +
                "This build resolved no adapters — reinstall Talos, or register one before starting a session."
        } else {
            fix = "No adapter named '\(name)' is registered. Set 'adapter:' in .talos/agents.yaml to one of: " +
                self.registeredNames.joined(separator: ", ") + "."
        }
    }
}

/// Resolves an `agents.yaml` `adapter:` name to an adapter.
///
/// Keyed on the name as written in the file, which is a **public config
/// contract**: everything under `.talos/` is plain text a user edits and
/// commits, so a registered name is never reused for a different meaning and
/// never renamed in place.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#adding-renaming-and-removing-a-type
///
/// Registration is a factory rather than an instance: an adapter holds a
/// single run, so each session resolves to its own.
///
/// Empty until something registers, and it knows no agent by name of its own —
/// a default would make one agent the answer to a name a user did not write.
public struct AgentAdapterRegistry: Sendable {
    private var factories: [String: @Sendable () -> any AgentAdapter] = [:]

    public init() {
        // No adapter is registered here. Wiring belongs to the layer that reads
        // `agents.yaml`, which is the only place that knows an agent's name.
    }

    /// The names that currently resolve, sorted.
    public var registeredNames: [String] {
        factories.keys.sorted()
    }

    /// Registers `factory` under `name`, which must be spelled exactly as
    /// `agents.yaml` spells it. Replaces any adapter already registered under
    /// that name.
    public mutating func register(_ name: String, factory: @escaping @Sendable () -> any AgentAdapter) {
        factories[name] = factory
    }

    /// Returns a fresh adapter for `name`, or throws ``UnknownAdapterError``.
    /// Never returns a substitute for a name it does not know.
    public func makeAdapter(named name: String) throws -> any AgentAdapter {
        guard let factory = factories[name] else {
            throw UnknownAdapterError(name: name, registeredNames: registeredNames)
        }
        return factory()
    }
}
