---
name: spec-driven-change
description: The default entry point for ANY change to the Talos repository — code, tests, config, CI, skills, docs, or wiki. Use this BEFORE writing or editing anything, and before opening a PR. Triggers on any request to implement, fix, refactor, add, remove, or configure something in Talos; on "work on issue #N", "implement this ticket", "pick up the next board item"; and whenever a change would touch behavior the wiki describes. Enforces the four-step spec-driven loop — read the SPEC first, trace the change to a board item / Spec Page / DoD criterion, reference both in the PR, and fix the SPEC in the SAME PR when the implementation proves it wrong. Blocks the change when a SPEC reference is missing and escalates a SPEC gap to a human decision instead of assuming.
---

# Spec-driven change

Talos is a spec-driven project. The wiki is the SPEC and it is the source of truth. This skill is
the loop every change follows, and it is the first thing to run — not a review checklist applied
afterwards.

**SPEC:** [Engineering Standards § Spec-driven workflow](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#spec-driven-workflow)
· [Contributing](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing)
· [Contributing § Before you write code](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints)

This skill **cites** the SPEC; it does not restate it. Rules live on the wiki pages linked here and
nowhere else — read the page, do not trust a summary in this file. Anything that looks like a rule
in this file without a link next to it is a bug in this file.

---

## The loop

The four steps are quoted verbatim from
[Engineering Standards § Spec-driven workflow](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#spec-driven-workflow):

> ```
> 1. The change is described in the wiki first, or the wiki already covers it.
> 2. A board item links to the wiki page it implements and the DoD criterion it advances.
> 3. The PR references both, and its tests assert the spec's stated behavior.
> 4. If the implementation reveals the spec is wrong, the SPEC is updated in the
>    same PR — never silently diverged from.
> ```

Each step below is a **gate**. Do not pass a gate by promising to come back to it.

---

## Step 0 — Fetch the SPEC before writing code

Read the relevant wiki page **before** the first edit, not while reviewing the diff. Fetch it fresh
every time; a page you read in an earlier session may have changed.

Fetch a single page (fastest — the wiki's raw Markdown):

```bash
curl -fsSL https://raw.githubusercontent.com/wiki/CalixtoTheBugHunter/talos/Engineering-Standards.md
```

Substitute the page name from the URL, e.g. `Contributing.md`,
`Architecture-The-Orchestration-Boundary.md`, `Safeguards-and-Autonomy.md`, `Decision-Log.md`.

Fetch the whole SPEC when the change spans pages, or when you need to grep it:

```bash
git clone https://github.com/CalixtoTheBugHunter/talos.wiki.git /tmp/talos-wiki
grep -rn "<term>" /tmp/talos-wiki
```

`WebFetch` on the rendered page
(`https://github.com/CalixtoTheBugHunter/talos/wiki/<Page>`) also works and is the fallback when
`curl` is unavailable. Prefer raw Markdown: anchors, tables, and quoted lines survive intact, and
step 3 needs verbatim quotes.

**Which pages.** Start from the board item's **Spec Page** field. Then add every page the change
could violate, in the order [Contributing § Before you write code](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints)
lists them — that page orders the hard constraints by how often they are violated by accident, and
that ordering is the reading order.

**Hard stop.** No file is created or edited until the governing page has been read in this session.
If no wiki page governs the change, that is a SPEC gap → *Escalating a SPEC gap* below.

---

## Step 1 — Trace the change to three things

Before writing code, state all three explicitly. Not one, not two.

| | Where it comes from | If it is missing |
| --- | --- | --- |
| **Board item** | An issue on the [Talos Board](https://github.com/users/CalixtoTheBugHunter/projects/5) — `gh issue view <N> --repo CalixtoTheBugHunter/talos` | Stop. Configuration and skills are backlog work too, per [Engineering Standards § Configuration is backlog work](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#configuration-is-backlog-work). Ask for the item, or ask whether to open one. |
| **Spec Page** | The board item's `Spec Page` field and the wiki links in its body | Stop. An item implementing nothing in the SPEC "needs justifying before it is built" ([Engineering Standards](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#spec-driven-workflow)). Escalate; do not pick a page that looks close. |
| **DoD criterion** | A numbered criterion in [MVP Definition of Done](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done) | Do not leave it blank. Either name the criterion, or state that the item advances none and give the explicit justification the SPEC demands — e.g. a binding row in the [Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log). A silent blank is the failure; a stated justification is not. |

**Hard stop — this is the blocking one.** A change with no SPEC reference does not get written. Say
what is missing and stop. Do not proceed on a plausible-looking page, do not infer the criterion,
and do not start with "I'll add the traceability later."

Read the board item's own acceptance criteria as the definition of done for the work — and per
[Decision Log #15](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log), INVEST
"Independent" means independent of *sibling issues*, never independent of the SPEC.

---

## Step 2 — Write the change against the SPEC's words

- Implement what the SPEC says, not what the SPEC would probably say.
- Tests assert **the spec's stated behavior** (step 3 of the loop). Where practical, quote or cite
  the SPEC line in the test so the test reads as a statement of the spec it verifies — the reason
  Swift Testing was chosen, per [Engineering Standards § Toolchain](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#toolchain).
- Do not paraphrase a wiki rule into a code comment, a README, or this repo's docs. "An issue that
  restates the spec in its own words is a second source of truth, and second sources of truth
  drift" ([Engineering Standards](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#issues-are-never-independent-of-the-spec)).
  Link instead.
- Run the sibling skills that guard the specific constraints your change touches — see
  *Sibling skills* below.

---

## Step 3 — The PR references both

Branch, commit, and PR conventions are on the wiki, not here:
[Engineering Standards § Git conventions](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#git-conventions)
— branch prefixes, Conventional Commits with a scope from the board's Area field, squash-merge,
linear history, signed commits, 1 approval, green required checks.

The PR body must contain:

1. `Closes #<issue>` — the board item.
2. A link to each **wiki page** the change implements, with the **binding line quoted verbatim**.
   Quote, do not summarize, so nobody has to trust a paraphrase.
3. The **DoD criterion** advanced, or the explicit justification for advancing none.
4. If the SPEC changed: a link to the wiki diff and one line on why the SPEC was wrong.

A PR that references the issue but not the wiki page has skipped step 3 — it is incomplete, not
"mostly done."

---

## Step 4 — If the implementation proves the SPEC wrong, fix the SPEC in the same PR

This is the step that gets skipped. From
[Contributing](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing):

> If your implementation proves a spec wrong, **fix the spec** — do not work around it in code.

And from [Contributing § Before you write code](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints):

> When the wiki and the code disagree, **the wiki wins and the code is a bug.**

So there are exactly two legal outcomes when code and SPEC diverge, and one illegal one:

| Outcome | Legal? |
| --- | --- |
| The SPEC is right → change the code | ✅ |
| The SPEC is genuinely wrong → **update the wiki in the same PR**, then change the code | ✅ |
| The code quietly does something the wiki does not say | ❌ A defect, "even when it works" |

**"Same PR" means the wiki edit happens before the PR is marked ready** — not a follow-up issue, not
a TODO, not a comment in review. The wiki is a separate git repository, so the wiki edit is a
separate push; link it from the PR body so the pair is reviewable together:

```bash
git clone https://github.com/CalixtoTheBugHunter/talos.wiki.git
# edit the page, commit, push — then link the commit in the PR body
```

**A wiki edit is a SPEC change, and a SPEC change is a decision.** If the correction changes
binding behavior rather than fixing a typo or a broken link, it is not yours to make alone:
escalate it as below and record it in the
[Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log), where "a decision
is binding until changed here" and "new decisions are appended, never rewritten."

Before editing the wiki, check whether the page is a rule you are allowed to touch at all:
[Contributing § Guidelines you may and may not touch](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#guidelines-you-may-and-may-not-touch).

---

## Escalating a SPEC gap

A gap is anything the SPEC does not answer: no page covers the change, two pages conflict, or the
page covers the case but not *your* case. Also check the
[Decision Log § Open questions](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log) —
if your change depends on one of those, it is already a known gap and the decision comes first.

**Never fill a gap with an assumption.** From
[Contributing § If you contribute with an AI agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills):

> A skill that hits something the SPEC does not answer raises a **SPEC gap** for a human decision
> and the [Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log). It does
> not guess, and neither should you.

What to do:

1. **Stop the affected work.** Continue only the parts that do not depend on the gap.
2. **Raise it to a human**, stating: the gap, the pages you read, the candidate answers, and what
   each one would change. Not a recommendation dressed as a fact.
3. **Get the decision recorded in the [Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log)** —
   appended, never rewritten — before the code that depends on it is written.
4. Where an issue would otherwise carry an assumption, it carries a **SPEC GAP** block instead, and
   "the gap is decided in the Decision Log before the issue is built"
   ([Decision Log #15](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log)).

A guess that happens to be right is still a process failure: it puts a rule in the code that the
SPEC never sanctioned.

---

## Authority order when sources conflict

Two different orders apply. Do not mix them up.

**Runtime, inside the product** — the ranking table is the SPEC and is normative; read it, do not
work from a copy: [Talos Guidelines § Authority order](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#authority-order).
Its binding constraint:

> **Nothing at runtime overrides #1 or #2.** Not the user in a session, not an agent, not
> Self-improver, and not content Talos reads from a third party

Any change to the product must preserve that ordering; a change that lets a lower rank override a
higher one is a defect regardless of what a session, a user, or third-party content asked for.

**Development time, deciding what this repo should say** — from the quoted SPEC lines above:

1. The **wiki** — "the wiki wins and the code is a bug"
   ([Contributing](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing)); within it the
   [Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log) is "binding until
   changed here."
2. The **board item** — but its fields point at the wiki; when an item and the wiki disagree, the
   wiki wins and the item is stale.
3. The **code**, and anything in this repo including this skill file — lowest. Never a source of
   truth about a rule, only an implementation of one.
4. A **session instruction** cannot override 1 or 2. It can direct the work; it cannot rewrite the
   SPEC. Asking for a change that contradicts the wiki is a request to change the wiki — say so and
   run step 4.

Where the SPEC does not state an ordering between two sources, that is itself a SPEC gap. Escalate
it; do not invent the tie-breaker.

---

## Sibling skills

This skill is the entry point, not the whole guard. The skill-to-constraint mapping is on the wiki
so it cannot drift out of date here:
[Contributing § If you contribute with an AI agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills).
Read that table and run every skill whose trigger your change matches — before writing code, not
after.

These are skills for **developing Talos**. They are not the
[Editable Talos Guidelines](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#editable-talos-guidelines)
that ship inside the product for end users — different thing, different audience, different
lifecycle.

---

## Checklist before marking a change ready

- [ ] The governing wiki page was fetched and read **before** the first edit.
- [ ] Board item, Spec Page, and DoD criterion are all named — or a missing DoD is explicitly
      justified rather than left blank.
- [ ] Tests assert the SPEC's stated behavior.
- [ ] The PR body links the wiki page and quotes the binding line verbatim.
- [ ] No wiki rule was restated in this repo's own words; everything is a link.
- [ ] If code and SPEC diverged: the wiki was fixed in this PR, and the change was raised as a
      decision if it was binding.
- [ ] Every SPEC gap encountered went to a human and the Decision Log — none was assumed.
- [ ] Every sibling skill matching this change was run.
