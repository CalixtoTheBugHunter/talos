import Foundation
import OSLog

/// Exports Talos's own log entries to a plain-text file, for attaching to a
/// bug report.
///
/// Reads only this process's entries via `OSLogStore(scope:
/// .currentProcessIdentifier)` — never a system-wide log, never a network
/// call — consistent with
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution#no-telemetry.
/// The caller decides the destination `URL`, which is how
/// https://github.com/CalixtoTheBugHunter/talos/issues/39's "requiring
/// explicit action" holds: nothing in this type writes anywhere on its own.
///
/// `.currentProcessIdentifier` is the only scope a non-entitled macOS app
/// can read via the public `OSLogStore` API — there is no way to read a
/// *previous* launch's history without Apple's private log-collection
/// entitlement. So this can only ever export the currently running
/// session, never a session that already crashed and relaunched. `export`
/// states that in the file itself (see `header` below) rather than only in
/// this comment, since the person reading the exported text is the one who
/// needs to know it.
public enum LogExporter {
    public enum ExportError: Error, Sendable {
        case storeUnavailable
        case writeFailed
    }

    /// Writes every entry under one of Talos's own module subsystems to
    /// `url` as plain text, one redacted line per entry, oldest first.
    public static func export(to url: URL) throws {
        let store: OSLogStore
        do {
            store = try OSLogStore(scope: .currentProcessIdentifier)
        } catch {
            throw ExportError.storeUnavailable
        }

        let talosSubsystems = Set(Log.Category.allCases.map(\.subsystem))

        let position = store.position(date: .distantPast)
        let entries: [OSLogEntryLog]
        do {
            entries = try store.getEntries(at: position).compactMap { entry -> OSLogEntryLog? in
                guard let logEntry = entry as? OSLogEntryLog, talosSubsystems.contains(logEntry.subsystem) else {
                    return nil
                }
                return logEntry
            }
        } catch {
            throw ExportError.storeUnavailable
        }

        let formatter = ISO8601DateFormatter()
        let header = """
        # Talos log export — this session only.
        # Relaunching Talos starts a new session; an earlier session's logs are not included here.

        """
        let body = entries
            .map { entry in
                let line = "\(formatter.string(from: entry.date)) [\(entry.category)] \(entry.composedMessage)"
                return LogRedaction.redacted(line)
            }
            .joined(separator: "\n")

        do {
            try (header + body).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.writeFailed
        }
    }
}
