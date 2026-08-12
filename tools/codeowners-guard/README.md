# codeowners-guard

Asserts that `.github/CODEOWNERS` still parses and still covers the paths
[Engineering Standards § Protection rules on `main`](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#protection-rules-on-main)
says are load-bearing. Without this, a typo in a pattern, a deleted line, or a renamed directory
disables ownership for that path with no red signal anywhere — CI stays green, because nothing looked.

The rule is on the wiki and is not restated here:

- [Engineering Standards § Protection rules on `main`](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#protection-rules-on-main) — the six categories, and why a mistake in `.github/CODEOWNERS` is unrecoverable rather than merely annoying
- [Engineering Standards § CI pipeline order](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order) — why this is a step inside `lint`, not a stage of its own
- [Decision Log § Process decisions](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions) — decision 62 (owner review on the high-risk paths) and decision 63 (the files that carry the list itself, which this guard does **not** cover — see below)

## Run it

```bash
tools/codeowners-guard/self-test.sh        # prove both checks still fail on a violation
tools/codeowners-guard/codeowners-guard.sh # check this repository's .github/CODEOWNERS
```

Both run in the `lint` job, self-test first. `codeowners-guard` is a **step inside `lint`**, not a
stage of its own, so it adds no required status check on `main` — the same precedent
[`design-guard`](../design-guard/README.md) sets.

## The two checks

| # | Check | How | What it catches |
| --- | --- | --- | --- |
| 1 | A parse error or an unresolvable owner | `gh api repos/<repo>/codeowners/errors?ref=<ref>` — GitHub's own validator, not a second parser this codebase would have to keep in sync with GitHub's | A syntax mistake, or an owner GitHub cannot resolve to a collaborator with access |
| 2 | The six SPEC categories stay covered | A representative example path per category, matched against `.github/CODEOWNERS`'s own patterns | A renamed or deleted line that leaves a category silently unowned |

Check 1 needs a **real, already-pushed ref** — GitHub is answering about content it holds, not
content handed to it in the request. In CI, `ref` is the commit Actions already checked out, so this
covers the actual PR. It needs no elevated permission: `gh api` reads with the default `contents:
read` token, given `GH_TOKEN` in the environment.

Check 2 is local and network-free. It understands two pattern shapes — the only two this repository's
`.github/CODEOWNERS` uses:

- a root-anchored directory, `/dir/sub/`
- a bare filename glob, `*sub*.ext`

A pattern written in a different shape (a non-anchored directory segment, a character class, `**`) is
not matched, and this guard would then report the category it covers as missing. That is a stated
limitation, not a silent gap: a false failure here is safe, because it fails closed rather than open,
and the fix is to extend `match_pattern` in `codeowners-guard.sh` before writing that shape.

## Why check 1 can't self-test with a fixture the way check 2 does

[`design-guard`](../design-guard/self-test.sh) and [`spec-guard`](../spec-guard/self-test.sh) both
prove themselves by generating a violating tree and running the real guard against it, entirely
locally. Check 1 asks GitHub about a **ref**, and a synthetic fixture that was never pushed has no
ref for GitHub to answer about — generating one for real would mean granting the `lint` job write
access to push a scratch commit on every PR run, a bigger security surface than this check should
open.

`self-test.sh` instead shadows `gh` on `PATH` with a stub that returns a canned response, and runs
`codeowners-guard.sh` in its ordinary, no-argument mode against the real (currently complete)
`.github/CODEOWNERS`. That proves the logic that turns GitHub's answer into a pass or a fail, without
a network call and without touching the remote repository.

## What this does NOT claim

| Gap | Why it is here rather than in a check |
| --- | --- |
| **Decision 63's addendum** — that `.github/CODEOWNERS` and `docs/github/` are themselves on the list | § Protection rules on `main` states this in the same sentence as the six categories, but as a separate clause introduced "per decision 63." This item's acceptance criteria scope check 2 to "the SPEC's six categories," so decision 63's addendum is not one of them. A guard covering it is a separate change against that specific line. |
| **Whether an owner is the *right* owner** | Check 1 reports only what GitHub's validator reports: a parse error or an owner it cannot resolve. Whether `@CalixtoTheBugHunter` should be the owner of a given path is a review judgement, not a grep. |
| **The live ruleset** | [`docs/github/verify-rulesets.sh`](../../docs/github/verify-rulesets.sh) asserts that — including `require_code_owner_review` itself. This directory asserts the *ownership file*; that script asserts the *ruleset* that makes the file binding. See [`docs/github/README.md`](../../docs/github/README.md). |
