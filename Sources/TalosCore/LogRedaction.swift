import Foundation

/// Redacts secret- and token-shaped substrings before they reach a logger.
///
/// Every call site that logs content Talos did not author itself — an
/// agent's output, a connector response, anything read rather than
/// constructed — routes it through `LogRedaction.redacted(_:)` first. This is
/// the enforcement for
/// https://github.com/CalixtoTheBugHunter/talos/issues/39's "Secrets, tokens,
/// and prompt contents are never logged," and its patterns deliberately
/// mirror the key shapes `tools/spec-guard/spec-guard.sh` already treats as
/// secrets, so the two checks agree on what a secret looks like.
public enum LogRedaction {
    /// Provider API-key shapes. Deliberately **not** a blanket "any long
    /// alphanumeric run" catch-all: that shape also matches a UUID or a hex
    /// digest — an ordinary, non-secret diagnostic identifier a log line
    /// exists to carry — so a catch-all this broad would defeat the
    /// debuggability this facade exists for. Each entry here is instead a
    /// named secret *shape*; a token whose provider isn't listed is a gap
    /// to name and add, not a reason to widen this back into a general
    /// long-string filter.
    private static let patterns: [NSRegularExpression] = [
        #"sk-ant-[A-Za-z0-9_-]{16,}"#,
        #"sk-[A-Za-z0-9]{32,}"#,
        #"AIza[0-9A-Za-z_-]{35}"#,
        #"AKIA[0-9A-Z]{16}"#,
        #"gh[ps]_[A-Za-z0-9]{20,}"#,
        #"github_pat_[A-Za-z0-9_]{20,}"#,
        #"glpat-[A-Za-z0-9_-]{16,}"#
    ].map { try! NSRegularExpression(pattern: $0) } // swiftlint:disable:this force_try

    /// Returns `text` with every matching substring replaced by
    /// `<redacted>`. Ordinary prose with no secret-shaped run in it comes
    /// back unchanged.
    public static func redacted(_ text: String) -> String {
        var result = text
        for pattern in patterns {
            let range = NSRange(result.startIndex..., in: result)
            result = pattern.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "<redacted>"
            )
        }
        return result
    }
}
