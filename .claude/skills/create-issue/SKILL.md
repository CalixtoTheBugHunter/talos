---
name: create-issue
description: Authoring, filing, rewriting, or closing an item on the Talos board. Use this whenever a backlog item is created or changed — "open an issue for X", "file a ticket", "add this to the board", "break this epic into sub-issues", "rewrite issue #N", "fill in the fields on #N", "this issue is missing its Spec Page", "close #N", "mark #N done". Also use it before turning a discovered TODO, bug, or follow-up into a board item. Enforces INVEST on every leaf, with Independent read as independent of SIBLING ISSUES and never independent of the SPEC; requires a Spec Page and a DoD criterion on every item; requires the binding SPEC lines quoted VERBATIM rather than paraphrased; requires the full board field set at creation, because filing and boarding are one act; raises a SPEC GAP block for a human decision instead of assuming; and closes an item criterion by criterion against evidence rather than asserting Done in a comment.
---

# Create issue

An issue is the unit that makes the SPEC enforceable, and authoring one is a gated step rather than
a note-taking one. This skill runs the gate — at creation, when an item is rewritten, and again
backwards when the item closes.

**SPEC:** [Engineering Standards § How an issue is authored: INVEST](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#how-an-issue-is-authored-invest)
· [§ Issues are never independent of the SPEC](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#issues-are-never-independent-of-the-spec)
· [§ The gate fires at creation](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-gate-fires-at-creation)
· [§ The board's field set](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-boards-field-set)
· [§ Epics are authored too](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#epics-are-authored-too-against-a-different-list)
· [§ The dev cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle)
· [§ Closing an item](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#closing-an-item-is-the-authoring-gate-run-backwards)
· [Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log)

This skill **cites** the SPEC; it does not restate it. Rules live on the wiki pages linked here and
nowhere else — read the page, do not trust a summary in this file. Anything that looks like a rule
in this file without a link next to it is a bug in this file.

Run [`spec-driven-change`](../spec-driven-change/SKILL.md) first. It owns the four-step loop, the
escalation procedure, and the authority order; this skill owns one step of it — step 2, where a
board item comes to exist — and defers to it rather than repeating it.

---

## When this fires

| Situation | Fires? |
| --- | --- |
| Opening a new issue, of any type | **Yes** |
| Adding an existing issue to the board, or filling a blank field on one | **Yes** — the gate did not fire yet, so it fires now |
| Rewriting an issue's body, criteria, or fields | **Yes** — a rewrite is a re-authoring |
| Splitting an issue, or breaking an epic into sub-issues | **Yes**, on each resulting leaf and on the epic |
| Closing an issue, or moving an item to `Done` | **Yes** — see [*Closing an item*](#closing-an-item-run-the-gate-backwards) |
| Implementing an item that already exists | No — [`execute-issue`](../execute-issue/SKILL.md) |
| Reviewing a PR against an item's criteria | No — [`review-pr`](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills) |
| Changing what the SPEC says | No — [`update-spec`](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills) |

Phrasings that fire it: "open an issue for…", "file a ticket", "add this to the board", "put this in
the backlog", "we should track this", "break this into sub-issues", "rewrite #N", "fix the fields on
#N", "close #N", "#N is done".

Configuration is not exempt. Skills, CI workflows, security configuration, and git protection are
[backlog work](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#configuration-is-backlog-work)
like everything else, so this skill fires on them too.

---

## Rule 1 — The gate fires at creation, as one act

Filing the issue and placing it on the board with every field set is a single operation. From
[Engineering Standards § The gate fires at creation](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-gate-fires-at-creation):

> **Filing the issue and placing it on the board with every field set is one act, and the gate fires
> on it.** There is no legal intermediate state where a Talos issue exists unauthored — not a draft
> in the repository, not a board item with blank fields, not a placeholder to be filled in later.

**Hard stop.** Do not run `gh issue create` until the body, the criteria, and every field value are
decided. "I'll open it now and fill in the Spec Page after" is the bypass this rule exists to close
— and per
[Decision Log #39](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log), an issue filed
now and boarded later "was authored by whoever boarded it, working from a title."

If a field cannot be decided because the SPEC does not answer it, that is a
[SPEC gap](#rule-5--an-uncovered-case-is-a-spec-gap-never-an-assumption), not a reason to file blank.

---

## Rule 2 — INVEST on every leaf, and `Independent` never means independent of the SPEC

Leaf issues follow [INVEST](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#issues-are-never-independent-of-the-spec),
and one letter is read wrong by default. Quoted verbatim:

> **Independent means independent of *sibling issues*** — you can pick one up without waiting
> on another. It does **not** mean self-contained. Every issue is *dependent* on the SPEC:

| Letter | What the gate checks on this issue |
| --- | --- |
| **I**ndependent | Buildable without waiting on a sibling — **and never independent of the SPEC** |
| **N**egotiable | States the outcome required, not the implementation someone already pictured |
| **V**aluable | Names who it is for and what changes for them |
| **E**stimable | Understood well enough to size; if it is not, the missing knowledge is the real issue |
| **S**mall | `Size` and `Estimate` are set, and [`Estimate` is whole days with a ceiling of three](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-boards-field-set) |
| **T**estable | Each criterion is checkable by inspection or by a test, not by opinion |

The dependence on the SPEC is the part that has teeth. Same section, verbatim:

> - It opens with the wiki pages it implements, and why each one binds it.
> - It quotes the binding lines **verbatim**, so nobody has to trust a paraphrase.
> - Its acceptance criteria trace to those lines rather than to someone's judgement.

**A leaf estimated above three days is split, not recorded.** The number is a signal, and
[Decision Log #38](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log) states why: with
no ceiling, `small` is taste, "and a letter enforced by taste is enforced differently by every
author."

INVEST does not apply to an epic. An epic is authored against
[a different list](#rule-6--an-epic-is-authored-against-a-different-list).

---

## Rule 3 — Spec Page and DoD on every item, or a justification stated first

Every item carries both, and neither is ever left blank. From
[Engineering Standards § Spec-driven workflow](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#spec-driven-workflow):

> an item that implements
> nothing in the spec, or advances no criterion, is an item that needs justifying before it is built.

| Field | Where the value comes from | If you cannot supply one |
| --- | --- | --- |
| **Spec Page** | The wiki page(s) the item implements — the page you read, not the page whose title matched | Stop. An item implementing no part of the SPEC is a [SPEC gap](#rule-5--an-uncovered-case-is-a-spec-gap-never-an-assumption): raise it and get the page written, or get the decision recorded. Do not pick a page that looks close. |
| **DoD** | A numbered criterion in [MVP Definition of Done](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done) | State the justification for advancing none **in the item body, before it is created** — e.g. a binding [Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log) row that mandates the work. A stated justification is legal; a blank is not. |

**The justification is written before creation, not after.** A blank field is invisible to review and
indistinguishable from an oversight, and the cost lands on whoever picks the item up —
[§ How an issue is authored](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#how-an-issue-is-authored-invest)
names the failure directly:

> An unauthored issue is cheap to file and expensive to build: the cost of a missing Spec Page is paid
> by whoever picks the item up, at the point where they have to guess what the SPEC meant, and their
> guess ships.

---

## Rule 4 — Binding SPEC lines are quoted verbatim, each page linked, each reason stated

For every Spec Page, the item body carries three things: the **link**, the **binding line quoted
verbatim**, and **one sentence on why that line binds this issue**. A link with no quote makes a
reader go find the line; a quote with no reason makes them guess which part of it matters.

Verbatim means character-for-character, in a blockquote, from the page's raw Markdown:

```bash
curl -fsSL https://raw.githubusercontent.com/wiki/CalixtoTheBugHunter/talos/Engineering-Standards.md
```

Substitute the page name from the wiki URL. Fetch fresh — a page read in an earlier session may have
changed, and a quote that was verbatim last week is a paraphrase now.

**A paraphrase is a blocking defect, not a style note.** Rewriting a SPEC line in the issue's own
words creates a second copy of the rule that no longer changes when the wiki changes. From
[§ Issues are never independent of the SPEC](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#issues-are-never-independent-of-the-spec):

> An issue that restates the spec in its own words is a second source of truth, and second sources of
> truth drift. Cite and quote instead.

Practically, when authoring or reviewing an item body:

- Every quoted line is diffed against the page's raw Markdown before the issue is filed.
- A line "quoted" with a word changed, a clause dropped, or emphasis moved is **not quoted**. Fix it
  or drop the claim.
- A summary of a section is not a quote of it. Quote the sentence that binds, and link the section
  for the rest.
- The trimmed-down phrasing that reads better is the one to reject. It reads better because it lost
  the qualifier that was doing the work.

---

## Rule 5 — An uncovered case is a SPEC GAP, never an assumption

Where the SPEC does not cover something, the item carries a **SPEC GAP** block and stops. From
[§ Issues are never independent of the SPEC](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#issues-are-never-independent-of-the-spec):

> - Where the SPEC does not cover something, the issue carries a **SPEC GAP** block instead of an
>   assumption, and the gap is decided in the [Decision Log](Decision-Log) before the issue is built.

[`spec-driven-change`](../spec-driven-change/SKILL.md) owns the escalation procedure — what to state,
who decides, and how it is recorded. This skill adds only what is specific to an item: the block goes
**in the item body**, and the item's Status goes to `Blocked` rather than `Ready`, because
[the dev cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle)
requires that "Nothing in it is still a SPEC gap" to leave `Ready`.

The block, in the item body:

```markdown
## SPEC GAP

**Question:** <the one thing the SPEC does not answer>
**Pages read:** <links — including the ones that came closest and why they do not cover this>
**Candidate answers:** <each option, and what each one would change about this issue>
**Blocks:** <which acceptance criteria cannot be written until this is decided>

Decision required in the Decision Log before this issue is built.
```

**Do not resolve a gap by writing a plausible acceptance criterion.** A criterion invented to fill a
gap is a rule entering the product through a ticket, and per
[Contributing § If you contribute with an AI agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills):

> A skill that hits something the SPEC does not answer raises a **SPEC gap** for a human decision
> and the [Decision Log](Decision-Log). It does
> not guess, and neither should you.

A gap in one field does not block the rest. Author everything that does not depend on the gap, then
stop on the parts that do.

---

## Rule 6 — An epic is authored against a different list

An epic groups sub-issues, so INVEST does not apply to it — but authoring still does. The list is on
the wiki at
[§ Epics are authored too](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#epics-are-authored-too-against-a-different-list);
read it there. Quoted verbatim:

> - **A Spec Page**, always. An epic implementing no part of the SPEC is a folder, not a board item.
> - **A DoD criterion**, or the same stated justification a leaf owes when it advances none.
> - **Sub-issues linked as GitHub sub-issues**, so progress rolls up rather than being narrated.
> - **A goal, and the condition under which the epic is done** — not the union of its leaves'
>   criteria, because an epic that is only its leaves needed no epic.
> - **No Size and no Estimate.** An epic's size is its sub-issues, and a number here competes with
>   them.

Sub-issues are linked as **native GitHub sub-issues** per
[Decision Log #13](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log), not as a task
list of checkboxes — see [*Board mechanics*](#board-mechanics) for the mutation. A checkbox list
looks like hierarchy on the issue page and rolls up nowhere.

---

## Rule 7 — Every field is set, and the labels agree with them

The field set, the values, and which items each field is required on are on the wiki:
[§ The board's field set](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-boards-field-set).
Read that table — it is the specification, and the nine fields are `Status`, `Priority`, `Size`,
`Estimate`, `Release`, `Area`, `Sub-function`, `Spec Page`, and `DoD`.

Two things about it are easy to get wrong:

- **`Size` and `Estimate` are for leaves only**, and blank on an epic. `Estimate` is in whole days.
- **`Sub-function` is set only on an item scoped to one.** An item spanning several is not "Shared"
  by default — `Shared` is a value with a meaning, so check the table rather than picking the
  catch-all.

`Status` is a state machine, not a label, and the states plus their gates are the
[dev cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle)
table. A newly authored item enters at `Backlog` — whose gate to leave is what this skill enforces:

> | **Backlog** | Authored against the SPEC. Not scheduled. | Human | Spec Page and DoD filled, binding lines quoted, INVEST holds |

Moving an item to `Ready` is not this skill's call; scheduling is a human's. What this skill can say
is whether the gate is met.

**Labels mirror the fields and never add to them.** Set `type:`, `P0`/`P1`/`P2`, `area:`, `fn:`, and
`release:` to match the field values, plus the [milestone](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#releases)
for the release. Per
[§ The board's field set](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-boards-field-set),
"**A label that disagrees with its field is a defect in the item**", so when a field changes, change
the label in the same operation.

---

## Closing an item: run the gate backwards

Closing is this skill's second job, and it is the authoring gate in reverse — the criteria this skill
wrote are the list it checks. From
[§ Closing an item is the authoring gate run backwards](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#closing-an-item-is-the-authoring-gate-run-backwards):

> **An item reaches Done criterion by criterion, and the
> [`create-issue` skill](Contributing#if-you-contribute-with-an-ai-agent-use-the-skills) closes it
> against the list it wrote.** Each acceptance criterion is named, and against each one either the
> evidence that met it or the reason it no longer applies. A criterion that cannot be evidenced is
> not met, and an item with an unmet criterion does not close — it goes back, or the criterion is
> struck with a reason recorded on the item.

So the closing comment is a table, one row per criterion, and nothing else counts:

```markdown
| # | Criterion | Evidence |
| --- | --- | --- |
| 1 | <the criterion, as authored> | <file:line, test name, PR link, or command + output> |
| 2 | … | **STRUCK** — <why it no longer applies> |
```

**Evidence is a thing a reader can open.** A file and line, a named test, a command and its output, a
link to the diff. "Implemented" is not evidence, "verified" is not evidence, and a checked box is not
evidence — per
[the dev cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle),
`Done` means:

> | **Done** | Merged, and its acceptance criteria were *verified* rather than asserted | — | — |

**One unmet criterion blocks the close.** The item goes back, or the criterion is struck with its
reason recorded on the item — and striking is a decision about scope, so raise it rather than
deciding it while closing.

This does not replace [`review-pr`](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills)
and is not made redundant by it. [Decision Log #40](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log)
draws the line: "a reviewer refutes a PR against the diff, an author confirms an item against its
ticket, and an item can pass review with a criterion nobody checked."

---

## The item body template

Structure, not prose to copy. Everything in angle brackets is decided before the issue is filed.

```markdown
## Goal

<what changes, and for whom — one paragraph>

## Spec Pages

- [<Page> § <Section>](https://github.com/CalixtoTheBugHunter/talos/wiki/<Page>#<anchor>) — <why this binds this issue>

  > <the binding line, quoted verbatim from the raw Markdown>

## DoD

<the numbered MVP DoD criterion advanced — or the justification for advancing none>

## Acceptance criteria

1. <checkable by inspection or by a test, and traceable to a quoted line above>
2. …

## Out of scope

- <what a reader would reasonably assume is included and is not>
```

Add a `## SPEC GAP` block if anything is uncovered. Omit `## Out of scope` only when there is
genuinely nothing a reader would assume.

---

## Board mechanics

The board is
[Talos Board, project 5](https://github.com/users/CalixtoTheBugHunter/projects/5). Both checkouts
live side by side and the repository must be named explicitly:

```bash
gh issue view <N> --repo CalixtoTheBugHunter/talos
gh issue create --repo CalixtoTheBugHunter/talos --title "…" --body-file /tmp/body.md \
  --label "type:chore,P1,area:skills,release:1.0.0-alpha" --milestone "v1.0.0-alpha"
```

Field values are set with `gh project item-edit`, which needs the project and field IDs. Discover
them rather than hardcoding a stale copy — a field ID pasted from a skill file is exactly the kind of
duplication this file avoids everywhere else:

```bash
gh project field-list 5 --owner CalixtoTheBugHunter --format json
gh project item-list 5 --owner CalixtoTheBugHunter --format json --limit 200
```

Linking a sub-issue needs the sub-issues feature header on the mutation:

```bash
gh api graphql -H "GraphQL-Features: sub_issues" -f query='
  mutation($parent: ID!, $child: ID!) {
    addSubIssue(input: {issueId: $parent, subIssueId: $child}) { subIssue { number } }
  }' -F parent=<parent node id> -F child=<child node id>
```

**Verify parentage on the issue, not on the board.** The board does not expose an item's parent or
its sub-issue roll-up through the project item API, so read `repository.issue.parent` and
`repository.issue.subIssues` instead. A board that looks right is not evidence the link exists.

---

## SPEC gaps this skill knows about

Open questions live in the [Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log);
check them before authoring, because an item that depends on one is blocked rather than ready.

| Gap | Current handling |
| --- | --- |
| Who moves an item from `Backlog` to `Ready`, and on what schedule | [The dev cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle) says `Human`, and names no scheduling rule. This skill reports that the gate is met and does not schedule. |
| Whether striking an acceptance criterion at close needs a Decision Log row or only a note on the item | [§ Closing an item](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#closing-an-item-is-the-authoring-gate-run-backwards) requires "a reason recorded on the item" and stops there. Record it on the item, and raise the strike rather than deciding it alone. |
| What `Priority` and `Release` should be when an item advances no DoD criterion | Not specified. Ask; do not default to `P2` / `Post-MVP` because it feels safe. |

A gap discovered while authoring goes to a human and the Decision Log — it does not get a row here
and a guess in the issue.

---

## Sibling skills

[`spec-driven-change`](../spec-driven-change/SKILL.md) runs first and owns the loop, the escalation
procedure, and the authority order. The full skill-to-constraint mapping is on the wiki so it cannot
drift here:
[Contributing § If you contribute with an AI agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills).

An issue whose subject matter touches a hard constraint is authored with that constraint's skill
read, because the acceptance criteria have to be writable without violating it — an item about
adapters, networking, tiers, or the budgets gets
[`agent-adapter`](../agent-adapter/SKILL.md),
[`orchestration-boundary`](../orchestration-boundary/SKILL.md),
[`safeguards-review`](../safeguards-review/SKILL.md), or `gates-check` accordingly.

---

## Checklist before creating or closing an item

Creating:

- [ ] The governing wiki page was fetched **fresh** and read, before the body was written.
- [ ] Body, acceptance criteria, and **every** field value are decided — nothing deferred to later.
- [ ] `Spec Page` names the page actually read; `DoD` names a criterion or carries the stated
      justification in the body.
- [ ] Every binding line is quoted **verbatim** in a blockquote, its page linked, and its reason for
      binding stated in one sentence.
- [ ] No SPEC rule is paraphrased anywhere in the body.
- [ ] Leaf: INVEST holds, `Size` and `Estimate` set, `Estimate` ≤ 3 whole days.
- [ ] Epic: Spec Page, DoD, goal, done condition, native sub-issues linked, no `Size`, no `Estimate`.
- [ ] Labels and milestone match the field values.
- [ ] Anything uncovered is a `## SPEC GAP` block with Status `Blocked` — nothing was assumed.

Closing:

- [ ] Every acceptance criterion is named in a table, in the order it was authored.
- [ ] Each row carries evidence a reader can open, or `STRUCK` with a reason recorded on the item.
- [ ] No criterion is marked met on the strength of the PR description.
- [ ] The item's `Status` moved to `Done` only after the table was complete.
