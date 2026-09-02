# dependency-age-guard

Asserts that a pull request bumping a dependency — a pinned GitHub Action, or a Swift package's
declared version requirement — to a version published less than a minimum age ago fails, per this
issue's acceptance criteria:

- [Issue #178](https://github.com/CalixtoTheBugHunter/talos/issues/178)
- [Safeguards & Autonomy § Dependency update age](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#dependency-update-age) —
  "A pull request that bumps a dependency — a GitHub Action or a Swift package — to a version
  published less than a minimum age ago is blocked from merging."
- [Decision Log #64](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions) —
  records the mechanism, the threshold, and the CI posture this file implements.

## Run it

```bash
tools/dependency-age-guard/self-test.sh                                                        # prove it still fails on a violation
BASE_SHA=<sha> HEAD_SHA=<sha> MIN_AGE_HOURS=24 tools/dependency-age-guard/dependency-age-guard.sh
```

Both run in the `lint` job, self-test first. This is a **step inside `lint`**, not a stage of its own,
so it adds no required status check on `main` — the same precedent
[`dependency-justification-guard`](../dependency-justification-guard/README.md),
[`workflow-hardening-guard`](../workflow-hardening-guard/README.md), and
[`codeowners-guard`](../codeowners-guard/README.md) set, per decision 64: this check "fails visibly in
CI the same way the gitleaks and dependency-review scans from issue #29 and issue #31 do, without
widening" the gap between `main`'s required contexts and what any workflow in this repo produces.

It runs only on the `pull_request` event, gated in `.github/workflows/ci.yml` — a push to `main` carries
no meaningful base to diff a bump against.

`MIN_AGE_HOURS` is never hard-coded in this script — decision 64 holds the threshold as "a single
configured value, never a number embedded in the check's logic". The one place `24` appears is
`DEPENDENCY_MIN_AGE_HOURS` in `ci.yml`'s top-level `env:` block, the same way `SWIFTLINT_VERSION` holds
the pinned linter version for that job.

## What it checks

| # | Check | How |
| --- | --- | --- |
| 1 | Whether a **GitHub Action's pinned SHA** changed | Compares `name<TAB>sha` pairs across every `.github/workflows/*.yml` file at `BASE_SHA` against `HEAD_SHA` |
| 2 | Whether a **Swift package's declared version requirement** changed | Compares `url<TAB>version` pairs parsed from `Package.swift`'s `.package(...)` declarations at `BASE_SHA` against `HEAD_SHA` |
| 3 | For each changed pin, how long ago that version was published | `gh api repos/<owner>/<repo>/commits/<ref>` — the pinned SHA for an Action, or the declared version (tried bare, then `v`-prefixed) for a Swift package — read as the commit's own `committer.date` |
| 4 | Whether that age is below `MIN_AGE_HOURS` | Fails the check, naming the dependency, its measured age, and the threshold |

A pin that is new at `HEAD` (absent at `BASE`) is treated the same as a changed one — a brand new
dependency's initial version is exactly as checkable as a bump of an existing one.

## Why Package.swift, not Package.resolved

`Package.resolved` — which records the *exact resolved* commit for a Swift package — is what
[`.gitignore`](../../.gitignore) excludes for this repository (`Package.swift` / SwiftPM section). There
is no committed `Package.resolved` at any ref to diff. `Package.swift`'s own `.package(url: "...", from:
"X.Y.Z")` declaration is what a PR actually changes when it bumps a Swift dependency, and it is exactly
what this issue's acceptance criterion names: "a pinned GitHub Action SHA or **a Swift package
requirement**" — the requirement, not the resolved revision.

GitHub's commits endpoint (`GET /repos/{owner}/{repo}/commits/{ref}`) accepts a tag name exactly as it
accepts a SHA, so the same lookup mechanism covers both dependency kinds: an Action's pinned SHA is
passed directly, and a Swift package's declared version is tried as a ref (bare, then `v`-prefixed, since
tagging conventions differ — confirmed against the real `jpsim/Yams` repository, which tags bare
`6.2.2` rather than `v6.2.2`).

## Why commit date, not a Release's `published_at`

Two readings of "published" were weighed. A GitHub Release's `published_at` is server-recorded and
cannot be backdated by whoever authored the underlying commit — the more tamper-resistant signal — but
requires a Release object to exist for the matching tag, which not every tagged repository creates. The
pinned commit's own `committer.date`, via the commits endpoint, is uniform across both dependency kinds
(both already resolve to a ref the same endpoint accepts) and needs no extra tag-to-release resolution.

This guard uses the commit date. The tradeoff — a crafted `committer.date` on the commit a tag points at
is not detected — is the same class of documented, review-enforced residue this repository's other
guards already carry rather than solve (e.g. `workflow-hardening-guard`'s fork-secrets and
`pull_request_target` checks). A future tightening to prefer a Release's `published_at` when one exists
is a narrower follow-up, not a reason to withhold the simpler, uniform check now.

## What this does NOT claim

| Gap | Why it is here rather than in a check |
| --- | --- |
| **A Swift package pinned by `branch:` or `revision:`** | Neither carries a version to age-check. Every current dependency (`Yams`) uses `from:`. |
| **A dependency hosted anywhere other than github.com** | The commits-API lookup is GitHub-specific. Every current dependency is GitHub-hosted; a non-GitHub `location`/`url` is reported as unresolvable rather than silently passed. |
| **A `.package(` call whose version sits inside a nested function call** (e.g. `.upToNextMajor(from: "1.0.0")` written across lines the chunk parser cannot separate from a sibling declaration) | The parser chunks on `.package(`, a bare `]`, or `targets:` — see `dependency-age-guard.sh`'s header for the exact boundary. This repository's manifest does not exercise that shape. |
| **A crafted `committer.date`** | See § Why commit date, above. |
| **The quality of a version bump, or whether it should have happened at all** | This only measures elapsed time since publish, per the SPEC line it implements. Whether the new version is otherwise safe is [`dependency-review.yml`](../../.github/workflows/dependency-review.yml)'s job (known vulnerabilities, license). |
