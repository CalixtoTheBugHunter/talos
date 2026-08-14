# Security Policy

## Reporting a vulnerability

**Primary path: [GitHub private vulnerability reporting](https://github.com/CalixtoTheBugHunter/talos/security/advisories/new),
enabled on this repository.** Use the **Report a vulnerability** button on the
[Security tab](https://github.com/CalixtoTheBugHunter/talos/security) — it opens a private draft
advisory visible only to you and the maintainer, and keeps the whole exchange (report, triage,
fix, disclosure) in one place.

If GitHub's reporting flow is unavailable to you, contact
[@CalixtoTheBugHunter](https://github.com/CalixtoTheBugHunter) directly as a fallback.

Do **not** open a public issue for a security vulnerability — especially anything touching the
sensitive areas below. This is the same procedure the wiki states in
[Contributing § Reporting security issues](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#reporting-security-issues);
this file exists in addition to that page because GitHub's own Security tab reads a repository-root
`SECURITY.md`, not the wiki.

## Sensitive areas

A report touching any of these gets priority triage, because a mistake here is the class of thing
Talos's own design is built to contain:

| Area | Why it matters |
| --- | --- |
| [Safeguards gate](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy) | The deny-by-default tier system that stands between an agent's intent and actual execution |
| Secret handling | Talos holds no model API keys; secrets live in the macOS Keychain only — [Technology & Distribution](https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution#decisions) |
| [Prompt injection](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#prompt-injection-posture) | Third-party content Talos reads (issues, PR comments, logs, web pages) must never raise a tier, grant an allowlist, or trigger an irreversible action |
| Subprocess spawning | [Only the agent adapter layer may spawn a process](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#only-the-adapter-layer-spawns-a-process); a spawn anywhere else, or a `stop` that leaves a child alive, is the failure mode this area exists to catch |
| Notarized-build supply chain | Codesigning, notarization, and the Homebrew cask update that ship a [tag-driven release](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#releases) |

## Scope

**In scope:** anything that lets an agent session bypass the Safeguards gate or escalate a tier
without approval, read or exfiltrate a secret, turn third-party content into an executed instruction,
spawn or escape a subprocess outside the adapter layer, or tamper with the signed/notarized release
artifact or its distribution path.

**Out of scope:** Talos runs
[unsandboxed by design](https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution#why-unsandboxed-is-safe-here) —
it must spawn agent CLIs and access project files freely, and restraint is enforced by the
Safeguards gate rather than by the OS sandbox. **Talos running unsandboxed is not itself a
vulnerability.** A report that Talos "can" read/write files or run processes, with no described way
past the gate, is expected behavior, not a finding.

## What to expect

- **Acknowledgement** within **3 business days** of a report through GitHub private vulnerability
  reporting.
- **Triage**, confirming whether the report is accepted and its severity, within **7 business
  days**.
- **Fix timeline**, once accepted, target by severity — communicated in the advisory, and extended
  with the reporter kept updated if the fix is more complex than expected:

  | Severity | Target |
  | --- | --- |
  | Critical | 30 days |
  | High | 60 days |
  | Medium / Low | 90 days, or folded into the next scheduled release |

## Coordinated disclosure

Public disclosure is coordinated with the reporter, defaulting to **90 days** after acknowledgement
or whenever a fix ships — whichever comes first — extendable by mutual agreement for a fix that
needs more time. The reporter is credited in the published advisory unless they ask to stay
anonymous.

## Supported versions

Talos is pre-1.0 ([`v1.0.0-alpha` milestone](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done)).
[Releases are tag-driven](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#releases)
and no maintenance branches exist —
[work happens on short-lived branches off `main`](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#branching),
which is always releasable. Only the **most recently published release** and **`main`** are
supported; an older alpha or beta build does not receive a backported fix — upgrade to the latest
release. This will be revisited once 1.0 ships and a version-support matrix has something to say.

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
