import OSLog

/// A logging facade over `OSLog`. No destination here is ever a network
/// endpoint — logs stay in the unified logging system on this machine.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution#no-telemetry
public enum Log {
    /// One identity for everything Talos owns, shared with
    /// `DatabaseLocation.bundleIdentifier` in `TalosPersistence` — kept as
    /// its own literal here because `TalosCore` has no dependency to share
    /// it from. Every module's subsystem (`Category.subsystem` below) is
    /// namespaced under this root rather than being a second identity.
    public static let rootIdentifier = "com.calixtothebughunter.talos"

    /// One category — and one distinct OSLog subsystem — per module in
    /// `ARCHITECTURE.md`, so a log line's origin is legible in Console.app
    /// without reading the call site. Raw values are the module names
    /// verbatim.
    public enum Category: String, CaseIterable, Sendable {
        case core = "TalosCore"
        case persistence = "TalosPersistence"
        case projectLibrary = "TalosProjectLibrary"
        case safeguards = "TalosSafeguards"
        case adapters = "TalosAdapters"
        case orchestration = "TalosOrchestration"
        case talosUI = "TalosUI"

        /// This module's own subsystem — `"com.calixtothebughunter.talos.<Module>"` —
        /// distinct per module rather than shared across all of them.
        public var subsystem: String {
            "\(Log.rootIdentifier).\(rawValue)"
        }
    }

    /// A `Logger` scoped to `category`'s own subsystem. Constructing an
    /// `os.Logger` is cheap and safe at each call site, so no caching layer
    /// sits in front of it.
    public static func logger(_ category: Category) -> Logger {
        Logger(subsystem: category.subsystem, category: category.rawValue)
    }
}

public extension Logger {
    /// Debug-level logging. `#if DEBUG` keeps this call — and the format
    /// string it captures — out of a Release build's binary entirely, rather
    /// than relying on `OSLog`'s own persistence policy for the `.debug`
    /// level to hide it at runtime.
    ///
    /// `.info`, `.notice`, `.error`, and `.fault` need no Talos wrapper:
    /// call them directly for a lifecycle event, a routine milestone, a
    /// recoverable failure, and an invariant violation respectively — that
    /// mapping is what "log levels used consistently" means here, and only
    /// `.debug` needs special handling to be compiled out.
    func talosDebug(_ message: @autoclosure () -> String) {
        #if DEBUG
            let text = message()
            debug("\(text)")
        #endif
    }
}
