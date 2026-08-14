# Security Policy

## Reporting a vulnerability

Do **not** open a public issue for a security vulnerability — especially anything touching the
[Safeguards gate](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy), secret
handling, or [prompt injection](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#prompt-injection-posture).
Contact [@CalixtoTheBugHunter](https://github.com/CalixtoTheBugHunter) directly. This is the same
procedure the wiki states in
[Contributing § Reporting security issues](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#reporting-security-issues)
— this file exists in addition to that page because GitHub's own Security tab reads a repository-root
`SECURITY.md`, not the wiki.

## Secret leak response

This repository never holds a real credential —
[Technology & Distribution](https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution#decisions)
fixes the macOS Keychain as the only sanctioned store, and [Project Library § Where it
lives](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives) states that
`.talos/` never carries one either — but three layers exist because a leak is still possible:

| Layer | Catches |
| --- | --- |
| [`.githooks/pre-commit`](.githooks/pre-commit), opt-in per clone | A secret before it leaves your machine |
| GitHub push protection | A secret at the moment of push, whether or not the hook is installed |
| The scheduled [`secret-scan-scheduled.yml`](.github/workflows/secret-scan-scheduled.yml) workflow, plus GitHub secret scanning | Everything already in history |

A confirmed detection from any of these — a GitHub secret-scanning alert, a failed
`secret-scan` CI step, or your own pre-commit hook catching something real rather than a test
fixture — is the response procedure below, not a decision to disable the layer that caught it.

1. **Rotate or revoke the credential immediately, before doing anything about the repository.**
   The commit is the second-order problem; the live credential is the first-order one. A secret
   that reached a public repository is compromised the moment it is pushed, whether or not anyone
   is known to have used it — assume it was seen.
2. **Removing the commit from history does not undo the exposure.** Forks, clones, cached views,
   and any scanner that already indexed the object may still hold it. Treat rotation as the fix and
   history cleanup as hygiene that happens after, not instead.
3. **History rewrite on `main` is not a step a contributor takes alone.** `git.history.rewrite`
   and `git.push.force` are exactly the class of action
   [Safeguards & Autonomy](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable)
   marks "**Never allowlistable**" for an autonomous agent working in this repository, and `main`
   itself is protected against a force-push and a non-fast-forward update per
   [Engineering Standards § Protection rules on `main`](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#protection-rules-on-main).
   Only the repository owner can rewrite pushed history, and only after rotation is already done.
4. **File the remediation privately first**, per the reporting procedure above, if the finding
   confirms a real credential — not a public issue, and not a description of the exposure until
   rotation is complete.
5. **Confirm the fix**, once rotated: the GitHub secret-scanning alert is marked resolved, and a
   re-run of `tools/secret-scan/secret-scan.sh detect` no longer reports the finding (or reports it
   only against history that predates the rotation, if the object itself was not removed).

## What is not a vulnerability report

A `secret-scan` CI failure or a pre-commit hook failure on a **deliberate test fixture** —
`tools/secret-scan/self-test.sh`'s own generated content, or a new test written the same way — is
expected behavior, not an incident. See
[`tools/secret-scan/README.md`](tools/secret-scan/README.md) for how that fixture is kept out of the
real scan surface without weakening it anywhere else.
