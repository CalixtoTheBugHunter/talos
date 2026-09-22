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
/// allowlist. The splitter models the operators that start a new command —
/// `&&`, `||`, `|`, `;`, a single `&`, newline — and **fails closed on any
/// shell construct it does not model**: command substitution (`$(…)`, a
/// backtick, a bare `$`), a redirect, a subshell, or an escape. Without that, a
/// dangerous neighbour attached by an unmodeled operator (`git push … & rm -rf`,
/// `git commit -m "$(rm -rf x)"`) would ride in as trailing tokens of a
/// recognized segment, which the subcommand parser ignores — laundering it into
/// that segment's allowlistable tier.
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
        // An empty result is the fail-closed outcome: the command is empty, or
        // it carries a shell construct the splitter does not model, so no
        // segment is trusted and the whole command falls to the default.
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
        // A `gh` op names no remote URL — it acts on the current repo (or a
        // `--repo owner/name` shorthand), so the gate resolves declared-ness
        // against whether a repo connector exists, never against a URL scanned
        // out of the arguments. Scanning would wrongly read a link or `@mention`
        // in a `gh pr comment` body as the remote.
        switch (group, rest.first) {
        case ("pr", "create"):
            return remoteWithoutExplicitURL(.gitPROpen)
        case ("pr", "merge"):
            return remoteWithoutExplicitURL(.gitPRMerge)
        case ("pr", "comment"), ("pr", "review"):
            return remoteWithoutExplicitURL(.gitPRComment)
        case ("repo", "delete"):
            return remoteWithoutExplicitURL(.gitRepoDelete)
        default:
            return nil
        }
    }

    // MARK: Builders

    private static func local(_ action: SafeguardsActionType) -> Recognition {
        Recognition(action: action, reachesRemote: false, explicitRemoteURL: nil)
    }

    /// A remote op whose command named the remote explicitly — `git push <url>`
    /// — so the gate can match that URL against a declared connector target.
    private static func remote(_ action: SafeguardsActionType, from arguments: [String]) -> Recognition {
        Recognition(action: action, reachesRemote: true, explicitRemoteURL: explicitRemoteURL(in: arguments))
    }

    /// A remote op reaching an implicit remote — the current repo, as every
    /// `gh` op does. The gate resolves declared-ness against whether a repo
    /// connector exists rather than a URL.
    private static func remoteWithoutExplicitURL(_ action: SafeguardsActionType) -> Recognition {
        Recognition(action: action, reachesRemote: true, explicitRemoteURL: nil)
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

    /// The metacharacters this recognizer does not model when they appear
    /// outside quotes — substitution (`$`, a backtick), redirects, a subshell,
    /// brace grouping, an escape. Each can execute or expand into a second
    /// command, and the subcommand parsers ignore trailing tokens, so any of
    /// them must fail the whole command closed rather than ride inside a
    /// recognized segment.
    private static let unmodeledOutsideQuotes: Set<Character> = ["$", "`", "<", ">", "(", ")", "\\", "{", "}"]

    /// A quote-aware, fail-closed scanner. It splits a command into shell
    /// segments on the operators that begin a new command — `&&`, `||`, `|`,
    /// `;`, a single `&`, and newlines — outside quotes, tokenizing each segment
    /// on whitespace with quotes stripped. It is deliberately shallow: enough to
    /// read a git invocation.
    ///
    /// It returns an **empty array to fail closed** — an unterminated quote, or
    /// an unmodeled construct (see ``unmodeledOutsideQuotes``) — so the whole
    /// command falls to the most-restrictive default rather than trusting a
    /// segment that swallowed something it did not parse.
    private static func splitIntoSegments(_ command: String) -> [[String]] {
        var segments: [[String]] = []
        var segment: [String] = []
        var token = ""

        func endToken() {
            guard !token.isEmpty else { return }
            segment.append(token)
            token = ""
        }
        func endSegment() {
            endToken()
            guard !segment.isEmpty else { return }
            segments.append(segment)
            segment = []
        }

        let scalars = Array(command)
        var index = 0
        while index < scalars.count {
            let character = scalars[index]
            switch character {
            case "'", "\"":
                guard let closing = scanQuote(scalars, from: index, delimiter: character, into: &token) else {
                    return []
                }
                index = closing
            case " ", "\t":
                endToken()
            case ";", "\n", "&", "|":
                endSegment()
                if isDoubledOperator(scalars, at: index) {
                    index += 1
                }
            case _ where unmodeledOutsideQuotes.contains(character):
                return []
            default:
                token.append(character)
            }
            index += 1
        }
        endSegment()
        return segments
    }

    /// Consumes a quoted run beginning at the opening quote `open`, appending
    /// its unquoted body to `token`. Returns the index of the closing quote, or
    /// `nil` to fail closed: an unterminated quote, or a `$`/backtick inside
    /// double quotes, where the shell still expands them. Single quotes make
    /// every character literal.
    private static func scanQuote(
        _ scalars: [Character], from open: Int, delimiter: Character, into token: inout String
    ) -> Int? {
        var index = open + 1
        while index < scalars.count {
            let character = scalars[index]
            if character == delimiter {
                return index
            }
            if delimiter == "\"", character == "$" || character == "`" {
                return nil
            }
            token.append(character)
            index += 1
        }
        return nil
    }

    /// Whether the operator at `index` is the doubled form `&&` or `||`, whose
    /// second character the caller then steps over.
    private static func isDoubledOperator(_ scalars: [Character], at index: Int) -> Bool {
        let character = scalars[index]
        guard index + 1 < scalars.count else { return false }
        let next = scalars[index + 1]
        return (character == "&" && next == "&") || (character == "|" && next == "|")
    }
}
