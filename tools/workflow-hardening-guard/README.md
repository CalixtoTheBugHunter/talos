# workflow-hardening-guard

Asserts every workflow under `.github/workflows/` follows the six rules
[§ Workflow hardening](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#workflow-hardening)
states, built for [issue #32](https://github.com/CalixtoTheBugHunter/talos/issues/32) — the release
workflow holds signing and notarization credentials, so a compromised third-party action anywhere in
`.github/workflows/` is a supply-chain risk, not only a CI concern.

## Run it

```bash
tools/workflow-hardening-guard/self-test.sh                     # prove it still fails on a violation
tools/workflow-hardening-guard/workflow-hardening-guard.sh      # check this repository's workflows
tools/workflow-hardening-guard/workflow-hardening-guard.sh <path>  # check <path>/.github/workflows only
```

Both run in the `lint` job, self-test first. This is a **step inside `lint`**, not a stage of its
own, so it adds no required status check on `main` — the same precedent
[`codeowners-guard`](../codeowners-guard/README.md),
[`pr-title-guard`](../pr-title-guard/README.md), and
[`dependency-justification-guard`](../dependency-justification-guard/README.md) set, per
[decision 64](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions).

The second form is **tree mode**, for `self-test.sh`: it runs every check against a synthetic
fixture tree that was never pushed, the same shape `codeowners-guard`'s tree mode uses.

## What it checks

| # | Check | How |
| --- | --- | --- |
| 1 | Every workflow declares an explicit top-level `permissions:`, defaulting to `contents: read` | The unindented `permissions:` block is required to exist and to name only `contents: read` (or nothing beyond it) |
| 2 | Elevated permissions are granted per-job, never workflow-wide | Any key other than `contents: read` inside the top-level `permissions:` block is a violation; the same key under `jobs.<job>.permissions` is not checked and is where it belongs |
| 3 | Every third-party action is pinned to a full commit SHA, not a tag | Every `uses: owner/repo[/path]@<ref>` line (excluding `./local-action` and `docker://`) requires `<ref>` to be exactly 40 hex characters |
| 4 | A comment beside each pin records the human-readable version | The same `uses:` line must carry a trailing `# <version>` comment |
| 5 | Workflows triggered by fork PRs never receive secrets | A file whose `on:` block names bare `pull_request` (not `_target`) may not reference `secrets.` anywhere in the file |
| 6 | `pull_request_target` is not used, or its use is justified in a comment | Every `pull_request_target` occurrence requires a comment containing "justif" within the three lines above it or the line itself |

## What this does NOT claim

| Gap | Why it is here rather than in a check |
| --- | --- |
| **Signing secrets are scoped to the release workflow only (issue #32's AC-7)** | No signing secret exists in this repository's workflows yet — there is no release workflow to scope one to. This guard enforces the *rules that have a subject today*; the criterion that needs one is on [issue #120](https://github.com/CalixtoTheBugHunter/talos/issues/120), where a signing secret first exists to scope. |
| **Whether check 5's `secrets.` reference is actually reachable from a fork PR** | It matches a bare textual `secrets.` against a file whose trigger includes `pull_request`. It does not trace which job or step gates that reference with an `if:` — the fix this rule asks for is to keep the secret out of a `pull_request`-triggered file entirely, not to prove a guard around it is airtight. |
| **Whether a `pull_request_target` justification is actually sound** | Check 6 requires a comment containing "justif" nearby, the same depth [`dependency-justification-guard`](../dependency-justification-guard/README.md) checks a justification box at — recognized and required, never graded. |
| **Arbitrary YAML** | Both `permissions:`/`on:` block parsing are line-oriented against this repository's own flat, non-anchored workflow style. A workflow using YAML anchors, flow-style mappings, or a deeply nested `on:` is outside what this guard understands. |
