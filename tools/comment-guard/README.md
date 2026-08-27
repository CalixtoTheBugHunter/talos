# comment-guard

The parts of [decision 70](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions)
that are mechanically checkable, turned into a check, plus the DocC abstract-length convention
[decision 76](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions) adds.

The rule is on the wiki and is not restated here:

- [Engineering Standards § Code comments explain the non-obvious, not the history](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#code-comments-explain-the-non-obvious-not-the-history)
- [Decision Log § Engineering decisions](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions) — decisions 70 and 76

## Run it

```bash
tools/comment-guard/comment-guard.sh     # scan this repository's tracked Swift files
tools/comment-guard/self-test.sh         # prove the rule still fails on a violation
```

Both run in the `lint` job, self-test first. `comment-guard` is a **step inside `lint`**, not a stage
of its own, so it adds no required status check on `main` — the same precedent
[`design-guard`](../design-guard/README.md) and [`pr-title-guard`](../pr-title-guard/README.md) set.

## What it checks

| # | Check | How |
| --- | --- | --- |
| 1 | A `TODO`, `FIXME`, or `XXX` marker on a full-line code comment | Word-bounded match against the comment text |
| 2 | An issue or PR reference on a full-line code comment | A bare `#123`, or a `github.com/.../issues/123` or `.../pull/123` URL |
| 3 | A `///` doc comment's first line (its DocC abstract) over 150 characters | DocC's own writing guidance recommends the abstract stay a plain-text, one-sentence summary at or under that length |

Only a **full-line** comment is scanned — one whose line, trimmed, starts with `//`. A trailing
comment after code on the same line is not, because it can follow a string literal containing `//`,
which this check cannot distinguish from a real comment start without a Swift parser.

Only `*.swift` files are scanned. Decision 70 is scoped to a "code comment"; this repository's own
tooling (shell scripts, workflow files) follows a different, already-established convention that cites
issues freely in its own header comments — see, for instance, this very file.

## What this does NOT claim

| Gap | Why it is here rather than in a check |
| --- | --- |
| **Redundancy, restatement, or narrated history in free prose** | Decision 70's general test — "would a reader lose anything if this were deleted" — is a judgement about meaning, not a spelling. It stays enforced by `review-pr`. |
| **A doc comment's total length** | Only the first line is capped. `Sources/TalosAdapters/AgentAdapter.swift`'s own protocol documentation legitimately runs past 20 lines with `- Parameters:`/`- Returns:`/`- Throws:` sections — a blanket cap on the whole comment would flag that accepted precedent rather than AI-produced bloat, so decision 76 rejected one. |
| **A file-header `//` banner's length or content** | Same reasoning — several already-reviewed headers run to 10 lines, and the drift this rule actually targets (a banner restating what the declaration's own doc comment already says) is a judgement, not a count. |
