# secret-scan

The `gitleaks` wrapper the CI stage and the pre-commit hook both call, so a secret staged locally and
a secret already pushed are caught by the same tool reading the same config:
[Engineering-Standards § Toolchain](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#toolchain).

The rules it enforces are on the wiki and are not repeated here — a copy would be a second source of
truth, and
[second sources of truth drift](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#issues-are-never-independent-of-the-spec):

| | |
| --- | --- |
| Why a secret in git is unrecoverable | [Technology-and-Distribution § Decisions](https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution#decisions) — `Secrets \| macOS Keychain only` |
| Why repository-side scanning exists | [Safeguards-and-Autonomy § What is never allowlistable](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable) — "Secret access or exfiltration" |
| Why the check runs as a step, not a stage | [Decision Log #56](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions), [#64](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions) |
| What to do about a real leak | [`SECURITY.md`](../../SECURITY.md) |

| File | What it does |
| --- | --- |
| [`secret-scan.sh`](secret-scan.sh) | Wraps `gitleaks detect` (git history, optionally restricted by `--log-opts`) and `gitleaks protect --staged` (the currently staged diff) against the committed [`.gitleaks.toml`](../../.gitleaks.toml) |
| [`self-test.sh`](self-test.sh) | Builds a throwaway git repository, plants a deliberate fixture credential, and confirms both modes fail on it — and pass on a clean one |

## Running it

```sh
tools/secret-scan/self-test.sh                 # prove the guard still fails on a violation
tools/secret-scan/secret-scan.sh detect         # scan this repository's full git history
tools/secret-scan/secret-scan.sh protect-staged # scan what is currently staged
```

Requires `gitleaks` (`brew install gitleaks`) — a missing binary fails with an install hint rather
than skipping the scan.

## What `detect` scans, and why two callers pass different flags

`gitleaks detect` walks git history from `HEAD`, or from whatever `--log-opts` restricts it to.
That one flag is the whole difference between the two CI callers:

- **The `lint` job**, on a pull request, passes `--log-opts` scoped to the PR's own commits — a
  secret already on `main` before this PR existed is not this PR's problem to fix, and scanning it
  again on every unrelated PR would make a finding impossible to attribute.
- **The scheduled workflow** passes no `--log-opts` restriction, so it walks every commit — the
  full-history check [issue #29](https://github.com/CalixtoTheBugHunter/talos/issues/29) requires
  precisely because a PR-scoped scan cannot catch something that reached `main` before the check
  existed.

`protect-staged` needs neither: the pre-commit hook only ever sees this one commit's staged diff.

## The one exclusion, and why it is not a tuning entry

**`tools/secret-scan/self-test.sh` is the only path `.gitleaks.toml` excludes.** Proving the scan
fails on a real violation means assembling a secret-shaped literal, and — per
[decision 66](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions) —
that literal is built from non-matching parts so it never appears whole in this script's own
committed source. The path exclusion is a second, independent layer on top of that discipline:
[`tools/spec-guard/spec-guard.sh`](../spec-guard/README.md) has the identical problem for its own
pattern table and solves it the same way — exclude the one file whose job is to construct the
violating shape. `self-test.sh` asserts the exclusion stays narrow — that this directory's other two
files carry no secret-shaped literal of their own.

Decision 66 exists because the path exclusion alone is not enough: a scanner — this repository's own
or a third party's — walks a pull request's full commit history, not only its head, so a contiguous
literal committed once and fixed in a later commit still reads as a leak on every subsequent scan.
That happened on this exact file's first commit, flagged by GitGuardian after `.gitleaks.toml`'s path
exclusion was already in place — the exclusion protects the *current* scan, and decision 66 is what
stops the literal from existing in history at all. See
[Engineering Standards § A scanner's self-test never commits its fixture whole](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#a-scanners-self-test-never-commits-its-fixture-whole).

This is structural, not a judgement that some class of secret is acceptable here. **The rest of
`.gitleaks.toml` extends gitleaks' full default ruleset (`useDefault = true`) and adds no other
exception** — this repository currently produces zero hits against the unmodified default rules
across its full history, so there is nothing else to tune. A future genuine false positive — a
recorded adapter-CLI fixture that happens to contain a secret-shaped placeholder, for instance —
gets its own allowlist entry, added under the same discipline
[`tools/spec-guard/spec-guard.sh`](../spec-guard/README.md) already applies to its own allowlist: a
citation of the SPEC or Decision Log entry that permits it, not a silent addition.

## What a green run does not claim

- **Not a replacement for GitHub secret scanning and push protection.** Those run against every push
  to every branch, including ones with no open PR; this tool only runs where CI or the pre-commit
  hook invokes it. See the repository's Security settings and [`SECURITY.md`](../../SECURITY.md).
- **Not a generic entropy scanner beyond what gitleaks' default ruleset already does.** A truly
  novel secret shape with no matching default rule and no added rule here passes silently, the same
  caveat [`spec-guard`](../spec-guard/README.md) states about its own greps.
