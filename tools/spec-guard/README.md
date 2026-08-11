# spec-guard

The `spec-guard` CI stage. It is the grep that
[MVP Definition of Done § Notes on the harder criteria](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#notes-on-the-harder-criteria)
says item 11 is checkable by, made permanent and required.

The rules it enforces are on the wiki and are not repeated here — a copy would be a second source of
truth, and
[second sources of truth drift](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#issues-are-never-independent-of-the-spec):

| | |
| --- | --- |
| The rule being enforced | [Architecture: The Orchestration Boundary](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary) |
| The criterion it automates | [MVP DoD #11](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#checklist) |
| Why it is a required check | [Engineering Standards § CI pipeline order](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order) · [Decision 11](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions) |
| The one module that may spawn | [§ Only the adapter layer spawns a process](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#only-the-adapter-layer-spawns-a-process) |

| File | What it does |
| --- | --- |
| [`spec-guard.sh`](spec-guard.sh) | Scans the repository's tracked files and exits non-zero on any hit, naming the SPEC rule and DoD #11 |
| [`self-test.sh`](self-test.sh) | Generates a deliberately violating tree and confirms the guard fails on it — and passes on a clean one |

## Running it

```sh
tools/spec-guard/self-test.sh    # prove the guard still fails on a violation
tools/spec-guard/spec-guard.sh   # scan this repository
```

Both are what CI runs, in that order. Neither needs a toolchain, a network, or a credential.

## Two things that look like exclusions

**`tools/spec-guard/` is not scanned.** A grep for a provider hostname necessarily contains that
hostname, and so does the self-test that writes the fixture, so the scanner cannot scan its own
pattern table. That is structural rather than a judgement about acceptable violations — and
`self-test.sh` asserts it stays narrow by checking this directory holds no Swift.

**The violating fixture is generated, never committed.** A provider hostname or a key-shaped literal
in a committed fixture is itself what DoD #11 forbids "anywhere in the Talos codebase", and exempting
its path would need an allowlist entry.

## Adding an allowlist entry

`ALLOWLIST` in [`spec-guard.sh`](spec-guard.sh) is **empty**, and `self-test.sh` asserts that it is.
An entry needs a `# SPEC: <wiki URL>` comment on its own line citing the decision that permits it,
and the guard fails the build when that comment is absent. A hard constraint is
[rejected rather than negotiated](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints),
so the decision belongs in the
[Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log) before the entry
exists.

## What a green run does not claim

Listed in the header of [`spec-guard.sh`](spec-guard.sh) rather than duplicated here. The short
version: it is not a generic secret scanner, it does not grep for a general HTTP client, and per
[`orchestration-boundary`](../../.claude/skills/orchestration-boundary/SKILL.md) it "greps for known
shapes, and a novel violation passes it." A green `spec-guard` is a grep having passed, not the
boundary having been reviewed.
