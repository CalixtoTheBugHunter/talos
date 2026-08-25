import Foundation
import Testing

/// Verifies debug logging is compiled out of Release builds structurally,
/// since a call `#if DEBUG` compiles away cannot be observed at runtime in
/// either configuration — the same reason `MinimumSupportedOSTests` checks
/// `@available` by reading source rather than by running on an old OS.
@Suite("Debug logging is compiled out of Release")
struct LogDebugCompiledOutTests {
    private static var logSourceText: String {
        get throws {
            var url = URL(fileURLWithPath: #filePath)
            while url.pathComponents.count > 1 {
                url.deleteLastPathComponent()
                let candidate = url.appendingPathComponent("Sources/TalosCore/Log.swift")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return try String(contentsOf: candidate, encoding: .utf8)
                }
            }
            fatalError("Could not locate Sources/TalosCore/Log.swift above \(#filePath)")
        }
    }

    @Test("talosDebug's call to Logger.debug sits inside #if DEBUG")
    func debugCallIsGuardedByDebugCompilationCondition() throws {
        let text = try Self.logSourceText

        guard let debugDirectiveRange = text.range(of: "#if DEBUG") else {
            Issue.record("Log.swift has no #if DEBUG block")
            return
        }
        let remainder = debugDirectiveRange.upperBound ..< text.endIndex
        guard let endDirectiveRange = text.range(of: "#endif", range: remainder) else {
            Issue.record("Log.swift has no #endif closing the #if DEBUG block")
            return
        }

        let guardedBody = text[debugDirectiveRange.upperBound ..< endDirectiveRange.lowerBound]
        #expect(guardedBody.contains("debug("))
    }
}
