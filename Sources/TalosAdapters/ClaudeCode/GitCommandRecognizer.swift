import TalosCore

/// Recognizes a `git` or `gh` operation inside the agent's `Bash` tool command
/// and maps it to its `taxonomy: 1` action type, so the gate classifies a
/// commit at its write tier and a force-push at the irreversible tier rather
/// than the single irreversible default a raw `Bash` tool name falls to.
/// The adapter parses the command because Claude Code runs `git`/`gh` through
/// `Bash`, so the operation lives in the command string, not the tool name —
/// and mapping the agent's own tool vocabulary is the adapter's work per
/// [decision 96](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions).
///
/// Pure and stateless. It **only narrows toward more restrictive**: a command
/// it cannot recognize whole returns `nil`, which the gate resolves at the
/// most-restrictive tier — never a permissive guess. A command that chains an
/// unrecognized segment onto a git op (`git commit && rm -rf x`) is therefore
/// `nil` too, so an unrecognized `rm` can never ride in under a `git.commit`
/// allowlist.
///
/// Talos does not determine whether a push targets a protected branch: branch
/// protection is enforced by git and the remote, not classified here, so every
/// push is `git.push` / `git.push.force`. See the git-recognition decision on
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log
enum GitCommandRecognizer {
    struct Recognition: Equatable {
        /// The taxonomy type the command's operations resolve to — the most
        /// restrictive when it carries more than one.
        let action: SafeguardsActionType
        /// Whether the operation reaches a remote (a push or a `gh pr`/`gh repo`
        /// op), so the gate applies the declared-repo check. A local op —
        /// `git.commit`, `git.branch.create` — does not.
        let reachesRemote: Bool
        /// An explicit remote URL the command named, for the gate to match
        /// against a declared connector target. `nil` for a bare remote name
        /// (`origin`) or a local op — the gate then checks whether the project
        /// declares a repo connector at all.
        let explicitRemoteURL: String?
    }

    /// The recognition for a `Bash` command, or `nil` when it is not a git/`gh`
    /// operation this recognizes whole.
    static func recognize(command: String) -> Recognition? {
        let segments = splitIntoSegments(command)
        guard !segments.isEmpty else { return nil }

        var recognitions: [Recognition] = []
        for segment in segments {
            guard let recognized = recognizeSegment(segment) else {
                // One unrecognized segment means the whole command falls to the
                // safe default — a recognized git op never launders an
                // unrecognized neighbour into its tier.
                return nil
            }
            recognitions.append(recognized)
        }

        // Most restrictive wins, the same principle `process.run` is classified
        // by: a command that can do the most dangerous of its operations is
        // classified by that operation.
        return recognitions.max { lhs, rhs in
            tierRank(lhs.action) < tierRank(rhs.action)
        }
    }

    // MARK: Segment recognition

    private static func recognizeSegment(_ segment: [String]) -> Recognition? {
        guard let executable = segment.first else { return nil }
        switch executable {
        case "git":
            return recognizeGit(Array(segment.dropFirst()))
        case "gh":
            return recognizeGH(Array(segment.dropFirst()))
        default:
            return nil
        }
    }

    private static func recognizeGit(_ tokens: [String]) -> Recognition? {
        // Skip git's own global options and their values, so `git -C path push`
        // reads as `push`.
        let arguments = stripGitGlobalOptions(tokens)
        guard let subcommand = arguments.first else { return nil }
        let rest = Array(arguments.dropFirst())

        switch subcommand {
        case "commit":
            // `--amend` rewrites history rather than adding a commit.
            if rest.contains("--amend") {
                return local(.gitHistoryRewrite)
            }
            return local(.gitCommit)
        case "push":
            if rest.contains(where: isForcePushFlag) {
                return remote(.gitPushForce, from: rest)
            }
            return remote(.gitPush, from: rest)
        case "rebase", "filter-branch", "filter-repo":
            return local(.gitHistoryRewrite)
        case "branch":
            return recognizeGitBranch(rest)
        case "checkout":
            // `git checkout -b <name>` creates a branch.
            return rest.contains("-b") ? local(.gitBranchCreate) : nil
        case "switch":
            // `git switch -c <name>` creates a branch.
            return (rest.contains("-c") || rest.contains("--create")) ? local(.gitBranchCreate) : nil
        default:
            return nil
        }
    }

    private static func recognizeGitBranch(_ rest: [String]) -> Recognition? {
        if rest.contains(where: { $0 == "-d" || $0 == "-D" || $0 == "--delete" }) {
            return local(.gitBranchDelete)
        }
        // `git branch <name>` creates; a bare `git branch` or `-a`/`--list`
        // lists, which mutates nothing and is not this recognizer's to gate.
        let positional = rest.first { !$0.hasPrefix("-") }
        return positional == nil ? nil : local(.gitBranchCreate)
    }

    private static func recognizeGH(_ tokens: [String]) -> Recognition? {
        guard let group = tokens.first else { return nil }
        let rest = Array(tokens.dropFirst())
        switch (group, rest.first) {
        case ("pr", "create"):
            return remote(.gitPROpen, from: rest)
        case ("pr", "merge"):
            return remote(.gitPRMerge, from: rest)
        case ("pr", "comment"), ("pr", "review"):
            return remote(.gitPRComment, from: rest)
        case ("repo", "delete"):
            return remote(.gitRepoDelete, from: rest)
        default:
            return nil
        }
    }

    // MARK: Builders

    private static func local(_ action: SafeguardsActionType) -> Recognition {
        Recognition(action: action, reachesRemote: false, explicitRemoteURL: nil)
    }

    private static func remote(_ action: SafeguardsActionType, from arguments: [String]) -> Recognition {
        Recognition(action: action, reachesRemote: true, explicitRemoteURL: explicitRemoteURL(in: arguments))
    }

    // MARK: Parsing helpers

    /// A remote argument that is a URL rather than a bare name (`origin`). Only
    /// a URL can be matched against a declared connector target; a bare name is
    /// resolved by whether the project declares a repo connector at all.
    private static func explicitRemoteURL(in arguments: [String]) -> String? {
        arguments.first { token in
            !token.hasPrefix("-")
                && (token.contains("://") || token.contains("@") || token.contains("github.com"))
        }
    }

    private static func isForcePushFlag(_ token: String) -> Bool {
        token == "--force" || token == "-f" || token.hasPrefix("--force-with-lease")
    }

    /// Drops `git`'s leading global options and the values of the two that take
    /// one (`-C <path>`, `-c <name=value>`), returning the subcommand and its
    /// arguments.
    private static func stripGitGlobalOptions(_ tokens: [String]) -> [String] {
        // `-C` and `-c` each consume the flag itself plus the one value it takes.
        let flagWithValueWidth = 2
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token == "-C" || token == "-c" {
                index += flagWithValueWidth
            } else if token.hasPrefix("-") {
                index += 1
            } else {
                break
            }
        }
        return Array(tokens.dropFirst(index))
    }

    /// The irreversible-tier types this recognizer emits, so the most
    /// restrictive of a chained command wins without reaching the classifier —
    /// which lives in a module `TalosAdapters` cannot depend on. Every other
    /// type this recognizer produces is write tier; it never produces a read
    /// type.
    private static let irreversibleActions: Set<SafeguardsActionType> = [
        .gitHistoryRewrite, .gitBranchDelete, .gitPushForce, .gitPRMerge, .gitRepoDelete
    ]

    private static func tierRank(_ action: SafeguardsActionType) -> Int {
        irreversibleActions.contains(action) ? 1 : 0
    }

    // MARK: Tokenizing

    /// Splits a command into shell segments on `&&`, `||`, `|`, `;`, and
    /// newlines, then each segment into whitespace tokens with surrounding
    /// quotes stripped. This is deliberately shallow: it is enough to read a
    /// git invocation, and any construct it does not model — a subshell, a
    /// backgrounded pipe, a variable — leaves a segment unrecognized, which is
    /// the safe outcome.
    private static func splitIntoSegments(_ command: String) -> [[String]] {
        // `&&` and `||` are two characters; a single `|`/`;`/newline is one.
        let twoCharOperatorWidth = 2
        var segments: [[String]] = []
        var current = ""
        let separators: Set<Character> = [";", "\n"]
        let scalars = Array(command)
        var index = 0
        func flush() {
            let tokens = tokenize(current)
            if !tokens.isEmpty {
                segments.append(tokens)
            }
            current = ""
        }
        while index < scalars.count {
            let character = scalars[index]
            let next = index + 1 < scalars.count ? scalars[index + 1] : nil
            if (character == "&" && next == "&") || (character == "|" && next == "|") {
                flush()
                index += twoCharOperatorWidth
                continue
            }
            if character == "|" || separators.contains(character) {
                flush()
                index += 1
                continue
            }
            current.append(character)
            index += 1
        }
        flush()
        return segments
    }

    private static func tokenize(_ segment: String) -> [String] {
        // A quoted token needs at least an opening and a closing quote to strip.
        let minimumQuotedLength = 2
        return segment
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map { token in
                var value = String(token)
                for quote in ["\"", "'"] {
                    if value.count >= minimumQuotedLength, value.hasPrefix(quote), value.hasSuffix(quote) {
                        value = String(value.dropFirst().dropLast())
                    }
                }
                return value
            }
            .filter { !$0.isEmpty }
    }
}
