# dependency-justification-guard

Asserts that a pull request adding a **new** dependency — a new `.package(` entry in
`Package.swift`, or a new GitHub Action `uses:` reference — carries a justification in the PR body,
per this issue's acceptance criteria:

- [Issue #31](https://github.com/CalixtoTheBugHunter/talos/issues/31) — "Adding a dependency requires
  justification in the PR, since KISS is a SPEC constraint"
- [Vision & Principles § Talos is not complicated](https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#talos-is-not-complicated) —
  "a small dependency surface is easier to keep safe"

## Run it

```bash
tools/dependency-justification-guard/self-test.sh                                              # prove it still fails on a violation
BASE_SHA=<sha> HEAD_SHA=<sha> PR_BODY=<body> tools/dependency-justification-guard/dependency-justification-guard.sh
```

Both run in the `lint` job, self-test first. This is a **step inside `lint`**, not a stage of its
own, so it adds no required status check on `main` — the same precedent
[`pr-title-guard`](../pr-title-guard/README.md), [`design-guard`](../design-guard/README.md), and
[`codeowners-guard`](../codeowners-guard/README.md) set.

It runs only on the `pull_request` event, gated in `.github/workflows/ci.yml` — a push to `main`
carries no PR body and no meaningful base to diff against.

## What it checks

| # | Check | How |
| --- | --- | --- |
| 1 | Whether a **new** Swift package was added | Compares the set of `url:` values inside `Package.swift`'s `dependencies:` array at `BASE_SHA` against `HEAD_SHA` |
| 2 | Whether a **new** GitHub Action was added | Compares the set of `uses:` action names (the part before `@`) across every `.github/workflows/*.yml` file at `BASE_SHA` against `HEAD_SHA` |
| 3 | If either set grew, whether the PR body checks the box | `- [x] New dependency added, justified below:` in the [PR template](../../.github/PULL_REQUEST_TEMPLATE.md)'s "Dependency justification" section |

## Why a version bump is exempt

**A routine Dependabot bump changes a pinned SHA or a version constraint, not the dependency's
identity** — the package's `url:`, or the action's `owner/repo[/path]` name, is unchanged. This guard
diffs the *identifier set*, not "did the manifest change at all", so a version bump needs no
justification and Dependabot's PRs are never blocked by it.

This mirrors the reasoning the sibling `dependency-age-guard` already states on the wiki: "this does
not slow or disable automatic updates" —
[Safeguards & Autonomy § Dependency update age](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#dependency-update-age).
A justification requirement that fired on every bump would be that same mistake in a different guard.

## What this does NOT claim

| Gap | Why it is here rather than in a check |
| --- | --- |
| **The justification text's accuracy or quality** | This checks that the box is checked, the same depth [`pr-title-guard`](../pr-title-guard/README.md) checks a `BREAKING CHANGE:` footer at — recognized and required, never graded. Whether the stated reason actually holds up is a review judgement. |
| **A dependency added and removed again within the same PR** | The comparison is `BASE_SHA` vs `HEAD_SHA` only. An intermediate commit that briefly added one is not what merges. |
| **Whether the new dependency crosses the orchestration boundary, or its license** | [`spec-guard`](../spec-guard/README.md) already scans `Package.swift`/`Package.resolved` for model-SDK/MCP-client shapes, and [`dependency-review.yml`](../../.github/workflows/dependency-review.yml) already checks license and known vulnerabilities. This guard only checks that a reason was written down. |
