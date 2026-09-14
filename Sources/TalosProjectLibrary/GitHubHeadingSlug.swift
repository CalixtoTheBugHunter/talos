/// Produces the anchor GitHub generates for a heading, so an indexed section's
/// anchor matches the one every SPEC link on the wiki already targets: lowercase,
/// punctuation dropped, spaces to hyphens, letters/digits/hyphens/underscores
/// kept. Duplicate slugs on one page are disambiguated with a `-1`, `-2` suffix,
/// the same way GitHub does.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#how-specs-are-retrieved
public enum GitHubHeadingSlug {
    /// The base slug for one heading, before any duplicate-disambiguation.
    public static func slug(for heading: String) -> String {
        var result = ""
        for character in heading.lowercased() {
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                result.append(character)
            } else if character == " " {
                result.append("-")
            }
            // Every other character — punctuation, symbols — is dropped, as GitHub does.
        }
        return result
    }

    /// The slug for `heading`, disambiguated against slugs already used on the
    /// same page in `seen`, which is updated with the returned slug.
    public static func uniqueSlug(for heading: String, seen: inout [String: Int]) -> String {
        let base = slug(for: heading)
        if let priorCount = seen[base] {
            let next = priorCount + 1
            seen[base] = next
            return "\(base)-\(next)"
        }
        seen[base] = 0
        return base
    }
}
