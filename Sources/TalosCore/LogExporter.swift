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
public enum LogExporter {
    public enum ExportError: Error, Sendable {
        case storeUnavailable
        case writeFailed
    }

    /// Writes every entry under `Log.subsystem` to `url` as plain text, one
    /// line per entry, oldest first.
    public static func export(to url: URL) throws {
        let store: OSLogStore
        do {
            store = try OSLogStore(scope: .currentProcessIdentifier)
        } catch {
            throw ExportError.storeUnavailable
        }

        let position = store.position(date: .distantPast)
        let entries: [OSLogEntryLog]
        do {
            entries = try store.getEntries(at: position).compactMap { entry -> OSLogEntryLog? in
                guard let logEntry = entry as? OSLogEntryLog, logEntry.subsystem == Log.subsystem else {
                    return nil
                }
                return logEntry
            }
        } catch {
            throw ExportError.storeUnavailable
        }

        let formatter = ISO8601DateFormatter()
        let text = entries
            .map { "\(formatter.string(from: $0.date)) [\($0.category)] \($0.composedMessage)" }
            .joined(separator: "\n")

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.writeFailed
        }
    }
}
