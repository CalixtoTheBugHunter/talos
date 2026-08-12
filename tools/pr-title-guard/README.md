# pr-title-guard

Asserts that a pull request's title follows
[Conventional Commits](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#conventional-commits).
Squash-merge makes the PR title the commit message, and `CHANGELOG.md` is generated from that
message — an unvalidated title is a broken release note.

The rule is on the wiki and is not restated here:

- [Engineering Standards § Conventional Commits](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#conventional-commits) — the exact grammar, the type table, the scope list, and the breaking-change syntax this guard enforces
- [Engineering Standards § CI pipeline order](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order) — why this is a step inside `lint`, not a stage of its own
- [Contributing § How to work: tests, commits, releases](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#how-to-work-tests-commits-releases) — commits and squash-merge PR titles follow Conventional Commits

## Run it

```bash
tools/pr-title-guard/self-test.sh                                    # prove it still fails on a violation
PR_TITLE='feat(core): add x' tools/pr-title-guard/pr-title-guard.sh  # check one title
```

Both run in the `lint` job, self-test first. `pr-title-guard` is a **step inside `lint`**, not a
stage of its own, so it adds no required status check on `main` — the same precedent
[`design-guard`](../design-guard/README.md) and [`codeowners-guard`](../codeowners-guard/README.md)
set. The check is still *required* in the sense the issue means: `lint` is already a required check
on `main`, so a title that fails this step fails `lint`, and `lint` gates the merge.

It runs only on the `pull_request` event, gated in `.github/workflows/ci.yml` — a push to `main`
carries no PR title in its event payload to check.

## What it checks

| # | Check | How |
| --- | --- | --- |
| 1 | The title matches `<type>(<scope>): <subject>` | A regex anchored on the exact type and scope lists below |
| 2 | The type is one of the nine the SPEC table lists | `feat fix docs chore perf refactor test build ci` |
| 3 | The scope is one of the twelve the SPEC lists | `core session safeguards project-library monitor ui a11y adapter ci security spec skills` |
| 4 | A breaking change is accepted, marked either way | `!` before the colon (`feat(core)!: …`), or a `BREAKING CHANGE:` footer line in the PR body — recognized and reported, never required, never rejected |

`PR_TITLE`/`PR_BODY` take priority over the positional arguments, so CI sets them from
`${{ github.event.pull_request.title }}` / `.body` and the title never crosses a shell
word-splitting boundary.

## What this does NOT claim

| Gap | Why it is here rather than in a check |
| --- | --- |
| **The `BREAKING CHANGE:` footer's own prose** | The footer lives in the PR body, not the title. This guard recognizes the line and reports it so a breaking-change PR is never rejected for using it, but it does not validate the description that follows the colon — that is a review judgement, not a grep. |
| **Subject length or casing** | The SPEC states neither a length limit nor a case convention for the subject beyond the examples it gives, so this guard enforces none. |
| **The commit body's actual conformance after squash-merge** | This checks the **PR title**, which becomes the squash commit's subject line. It does not re-check the commit after merge — by the time it exists, the title that produced it already passed this guard. |
