# Claude Skills

The skills in this directory are how an agent contributing to Talos learns the constraints **before**
writing code rather than being reminded of them in review.

This file is an **index of what is in this repository**. It is not a source of truth about any rule.
Every rule lives on the [wiki](https://github.com/CalixtoTheBugHunter/talos/wiki), each skill cites
the wiki page it enforces, and the authoritative skill-to-constraint mapping is the wiki's own table
— **[Contributing § If you contribute with an AI agent: use the skills](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills)**.

Read that table for what a skill enforces. Read this file for what is *here*, and which
`SKILL.md` to open. Anything in this file that looks like a rule without a link next to it is a bug
in this file.

---

## These are skills for developing Talos, not the guidelines that ship in the product

From [Contributing § If you contribute with an AI agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills):

> These are skills for **developing Talos**. They are *not* the
> [Editable Talos Guidelines](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#editable-talos-guidelines)
> that ship inside the product for end users — different thing, different audience, different
> lifecycle.

| | These skills | [Editable Talos Guidelines](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#editable-talos-guidelines) |
| --- | --- | --- |
| Live in | `.claude/skills/` in this repository | `.talos/guidelines/` in a *user's* project |
| Audience | Agents and humans contributing to Talos | End users of Talos, per project |
| Edited by | Talos contributors, via a reviewed PR | Users and [Self-improver](https://github.com/CalixtoTheBugHunter/talos/wiki/Sub-function-Self-improver) |
| Govern | How this repository is changed | How the sub-functions behave for that project |

The [Root Talos Guidelines](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#root-talos-guidelines)
are a third thing again — compiled into the app, shipped via releases. Which of the two guideline
kinds you may edit is settled by
[Contributing § Guidelines you may and may not touch](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#guidelines-you-may-and-may-not-touch).

---

## Two kinds of skill

[Decision 30](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions) makes
the split binding:

> A workflow skill owns a transition in the
> [dev cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle)
> and is
> the entry point for it; a constraint skill guards one hard constraint and is invoked by whichever
> workflow skill is active. Collapsing the two makes every constraint skill re-specify the workflow,
> and a rule stated in five places drifts in four of them.

So: **a workflow skill is an entry point; a constraint skill is not.** You start from a workflow
skill, and it runs the constraint skills whose triggers your change matches.

---

## Workflow skills

Listed in the order a change meets them, matching
[the wiki's table](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills).
The **dev-cycle transition** column is the
[Status](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle)
transition each one owns.

| Skill | In repo | Fires on | Dev-cycle transition it owns | Enforces |
| --- | --- | --- | --- | --- |
| [`spec-driven-change`](spec-driven-change/SKILL.md) | ✅ | Any Talos change — code, tests, config, CI, skills, docs, or wiki | None singly; it precedes every transition and is the default entry point | The [four-step loop](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#spec-driven-workflow) — SPEC read first, change traced to a board item / Spec Page / DoD criterion, both referenced in the PR, SPEC fixed in the same PR when the implementation proves it wrong |
| [`create-issue`](create-issue/SKILL.md) | ✅ | Authoring, filing, or rewriting a board item — and closing one | `Backlog` entry, and `In review` → `Done` | [INVEST](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#how-an-issue-is-authored-invest) on every leaf, the [full field set](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-boards-field-set), binding lines quoted verbatim, a **SPEC GAP** block instead of an assumption, and [closing criterion by criterion](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#closing-an-item-is-the-authoring-gate-run-backwards) |
| [`execute-issue`](execute-issue/SKILL.md) | ✅ | Implementing a board item | `Ready` → `In progress` → `In review` | [RIPER-5](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#riper-5-how-an-agent-executes-an-issue) — no Execute without an approved Plan, a deviation mid-Execute [returns to Plan](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#riper-5-how-an-agent-executes-an-issue), and a SPEC gap moves the item to [`Blocked`](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle) rather than being settled in code |
| [`review-pr`](review-pr/SKILL.md) | ✅ | Reviewing a PR, approving one, or asking whether it can merge | Leaving `In review` — on findings, [back to `In progress`](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#a-failed-review-returns-the-item-to-in-progress) | [Adversarial review](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#review-is-adversarial-by-default) — refute the change, verify every acceptance criterion against the diff, the tests, and every constraint page touched; [step 4](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#spec-driven-workflow) or not mergeable; and that an agent's review is [a self-check, not the approval](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#who-reviews) |
| [`update-spec`](update-spec/SKILL.md) | ✅ | Changing the wiki — including [step 4](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#spec-driven-workflow) firing mid-implementation | None — it is the gate on the SPEC itself, and on leaving `Blocked` | That a SPEC change is a [decision](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log), that binding changes are appended rather than rewritten, the [may-and-may-not-touch](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#guidelines-you-may-and-may-not-touch) split, and that the [authority order](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#authority-order) survives the edit |

**All five workflow skills are in the repo.** `spec-driven-change` still runs first on every change —
it covers any Talos change and is the default entry point — and the others own the transitions listed
above. A change that matches none of the four specific ones is not unguarded; it is guarded by
`spec-driven-change` plus the constraint skills.

---

## Constraint skills

Run by whichever workflow skill is active, for the constraints the change touches. All four are in
the repo. The order is
[Contributing § Before you write code](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints)'s
order, which is "how often they get violated by accident".

| Skill | Fires on | Enforces | Wiki pages it enforces |
| --- | --- | --- | --- |
| [`orchestration-boundary`](orchestration-boundary/SKILL.md) | Networking, adapters, MCP, credentials, subprocess spawning, cost parsing — and any request that has Talos "ask the model", "summarize", or "proxy the agent's traffic" | The one rule, and that a feature needing a direct model call is **out of scope** rather than built | [Architecture: The Orchestration Boundary](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary), incl. [only the adapter layer spawns a process](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#only-the-adapter-layer-spawns-a-process) · [MVP DoD #11](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done) |
| [`safeguards-review`](safeguards-review/SKILL.md) | Autonomy tiers, the gate, allowlists, action classification, approval UI, denials, audit logging | The [tier model](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#tiers), the [never-allowlistable](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable) set, no dark patterns on approval, [fail closed](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed), and third-party content as data | [Safeguards & Autonomy](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy), incl. the [action-type taxonomy](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy) and [prompt-injection posture](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#prompt-injection-posture) · [Vision § not a place for deceptive design](https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#talos-is-not-a-place-for-deceptive-design) |
| [`agent-adapter`](agent-adapter/SKILL.md) | Adapter work — the protocol, registry, process lifecycle, output parsing, token reporting | The six capabilities, and that **no Talos core file changes**; a needed core change is reported as a core bug | [Architecture § Agent adapters](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#agent-adapters) · [Contributing § an agent adapter](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#the-easiest-high-value-contribution-an-agent-adapter) |
| [`gates-check`](gates-check/SKILL.md) | UI, memory, launch, injected prompt context, timers, charts, metrics | The eight [budgets](https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable) and the [accessibility gate](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#accessibility), and that a gate failure blocks the release rather than becoming a follow-up | [Vision § Budgets](https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable) · [Essential Tools § Accessibility](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#accessibility) · [Foundations: Accessibility](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility) · [MVP DoD #9 and #10](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done) |

Each skill's own frontmatter `description` is the full trigger, including the phrasings that
typically precede a violation. This table is a summary of it; the `SKILL.md` is not.

---

## A SPEC gap goes to a human, never to an assumption

The rule every skill in this directory shares, from
[Contributing § If you contribute with an AI agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills):

> A skill that hits something the SPEC does not answer raises a **SPEC gap** for a human decision and
> the [Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log). It does not
> guess, and neither should you.

A gap is anything the SPEC does not answer: no page covers the change, two pages conflict, or a page
covers the general case but not yours. The procedure is
[`spec-driven-change` § Escalating a SPEC gap](spec-driven-change/SKILL.md#escalating-a-spec-gap),
and it is:

1. **Stop the affected work** — continue only what does not depend on the gap. Per
   [Decision 28](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions),
   the board item moves to `Blocked`, which is
   [a real destination](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle)
   rather than a failure to try harder.
2. **Raise it to a human** — the gap, the pages read, the candidate answers, and what each would
   change.
3. **Get the decision recorded in the [Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log)**,
   appended and never rewritten, *before* the code that depends on it is written.
4. Where an issue would otherwise carry the assumption, it carries a **SPEC GAP** block instead
   ([Decision 15](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions)).

A guess that turns out to be right is still a process failure: it puts a rule in the code that the
SPEC never sanctioned.

---

## Where the SPEC wins

When this repository and the wiki disagree, the wiki wins —
[Contributing](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing):

> This wiki is the **SPEC-driven source of truth**. When the wiki and the code disagree, **the wiki
> wins and the code is a bug.**

That includes this file and every `SKILL.md` beside it. A skill that has drifted from the wiki is a
bug in the skill, and the fix is to repoint the skill — not to leave the wiki matching it.
[`spec-driven-change` § Authority order](spec-driven-change/SKILL.md#authority-order-when-sources-conflict)
has the full ordering, and
distinguishes it from the [runtime authority order](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#authority-order)
inside the product, which is a different ranking for a different purpose.

---

## Why the skills were built before the product

From [Decision 17](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions),
which sets the [build order](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#build-order):

> **The Claude Skills.** Talos is a SPEC-driven project, so the first deliverable is the tooling that
> makes the SPEC enforceable by the agents doing the building

And they are on the board rather than set up on the side, per
[Decision 16](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions) and
[Engineering Standards § Configuration is backlog work](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#configuration-is-backlog-work):

> Configuration created off-board is configuration nobody reviewed against the SPEC.

Every skill here traces to an item under
[EPIC #2](https://github.com/CalixtoTheBugHunter/talos/issues/2).
