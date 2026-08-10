---
name: update-spec
description: Changing what the SPEC says — any edit to the Talos wiki. Use this whenever the wiki is to be updated, corrected, extended, or created: "update the wiki", "fix the spec", "the spec is wrong", "the wiki says X but the code does Y", "add a wiki page", "document this on the wiki", "record this decision", "add a decision to the Decision Log", "answer this open question", "clarify that section", "fix this typo on the wiki", "the anchor is broken". Also fires mid-implementation the moment step 4 of the spec-driven loop is reached — when an implementation reveals the spec is wrong, the SPEC is updated in the same PR and never silently diverged from — and when leaving Blocked, whose gate is that the gap is decided in the Decision Log. Separates a non-binding fix (typo, broken link, clarification that changes no behavior) from a binding change, which is a decision and is recorded in the Decision Log where a decision is binding until changed there. Enforces that decisions are appended and never rewritten, so a reversal leaves the old row in place and adds a superseding row; enforces the may-and-may-not-touch split, so Root Talos Guidelines are Talos developers only and no decision whose AI-editable column reads Never is edited; requires the authority order to survive the edit, treating an edit that lets a lower rank override a higher one as a defect; requires a SPEC change that settles an open question to remove that row and append a numbered decision in the same edit; requires the wiki edit to land in the same change as the code, before the PR is marked ready, never as a follow-up issue and never as a TODO; requires the wiki commit to follow Conventional Commits with the spec scope in the separate wiki git repository, linked from the PR body; requires a new page in the sidebar with no dangling cross-page link or anchor; forbids a second source of truth, so a rule lives on exactly one page and every other page links to it; and raises a binding change that is a human decision rather than making it alone.
---

# Update SPEC

The only skill that **writes** the SPEC. Every other skill points at the wiki and is bound by it; this
one changes what the others are bound by, which is why it carries the heaviest gates in the repository.

**SPEC:** [Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log)
· [§ Open questions](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#open-questions)
· [Engineering Standards § Spec-driven workflow](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#spec-driven-workflow)
· [§ Issues are never independent of the SPEC](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#issues-are-never-independent-of-the-spec)
· [§ The dev cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle)
· [§ Conventional Commits](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#conventional-commits)
· [§ Branching](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#branching)
· [Contributing § Guidelines you may and may not touch](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#guidelines-you-may-and-may-not-touch)
· [Contributing § If you contribute with an AI agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills)
· [Contributing § Before you write code](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints)
· [Talos Guidelines § Authority order](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#authority-order)
· [§ Root Talos Guidelines](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#root-talos-guidelines)
· [§ Editable Talos Guidelines](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#editable-talos-guidelines)
· [Foundations: Tone § A decision goes to the user as a poll](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Tone#a-decision-goes-to-the-user-as-a-poll)

This skill **cites** the SPEC; it does not restate it. Rules live on the wiki pages linked here and
nowhere else — read the page, do not trust a summary in this file. Anything that looks like a rule in
this file without a link next to it is a bug in this file.

This is a **workflow skill**. Per
[Decision 30](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions), a
workflow skill "owns a transition in the [dev cycle](Engineering-Standards#the-dev-cycle) and is the
entry point for it." This one owns the gate on the SPEC itself, and the exit from
[`Blocked`](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle),
whose gate to leave is "The gap is decided in the [Decision Log](Decision-Log)."

Run [`spec-driven-change`](../spec-driven-change/SKILL.md) first. It owns the four-step loop, the
escalation procedure, and the authority order; this skill owns step 4 of that loop — the edit itself —
and defers to it rather than repeating it.

The scope of this skill is not invented here. It is already a row on the wiki's own skills table,
[Contributing § If you contribute with an AI agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills):

> | `update-spec` | changing this wiki | That a SPEC change is a [decision](Decision-Log), that binding changes are appended there rather than rewritten, and the [may-and-may-not-touch](#guidelines-you-may-and-may-not-touch) split |

---

## When this fires

| Situation | Fires? |
| --- | --- |
| Any edit to any wiki page — new page, new section, changed line, deleted line | **Yes** |
| A typo, a broken link, a dead anchor, a formatting fix on the wiki | **Yes** — see [Rule 1](#rule-1--a-non-binding-fix-and-a-binding-change-are-different-acts); it is the non-binding path, not the no-skill path |
| Mid-implementation, the moment the code and the wiki disagree | **Yes** — that is [step 4](#rule-6--the-same-change-as-the-code-before-the-pr-is-ready), and it fires *before* the workaround is written |
| Recording a decision, or answering an [open question](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#open-questions) | **Yes** — [Rules 1](#rule-1--a-non-binding-fix-and-a-binding-change-are-different-acts), [2](#rule-2--appended-never-rewritten), and [5](#rule-5--settling-an-open-question-moves-the-row-in-the-same-edit) |
| Moving an item out of `Blocked` | **Yes** — that is the transition this skill owns |
| A session instruction that contradicts the wiki | **Yes** — per [`spec-driven-change` § Authority order](../spec-driven-change/SKILL.md#authority-order-when-sources-conflict), asking for a change that contradicts the wiki is a request to change the wiki |
| Writing code that implements what the wiki already says | No — [`execute-issue`](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills) |
| Authoring, rewriting, or closing a board item | No — [`create-issue`](../create-issue/SKILL.md) |
| Reviewing a PR, including one that carries a wiki edit | No — [`review-pr`](../review-pr/SKILL.md), which reviews the edit this skill made |
| Editing `.talos/guidelines/` in a *user's* project | No — those are [Editable Talos Guidelines](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#editable-talos-guidelines), a different thing with a different lifecycle |

Phrasings that fire it: "the spec is wrong", "update the wiki", "the wiki says X but the code does Y",
"document this", "record this decision", "add a page for…", "clarify that section", "answer the open
question about…", "fix the anchor", "just a typo on the wiki".

"Just a typo" is in that list deliberately. The skill still runs, and it runs quickly —
[Rule 1](#rule-1--a-non-binding-fix-and-a-binding-change-are-different-acts) exists to let a genuinely
non-binding fix through without ceremony, and the classification is the part that cannot be skipped.

---

## Rule 1 — A non-binding fix and a binding change are different acts

**Classify the edit before making it, and state the classification.** The two paths differ in what they
require, so an unclassified edit takes the cheaper one by default — which is how a binding change gets
made without a decision behind it.

| | Non-binding fix | Binding change |
| --- | --- | --- |
| What it is | A typo, a broken link, a dead anchor, formatting, a clarification that changes **no** behavior | Anything that changes what Talos does, what is allowed, what is required, or what a reader would build differently |
| Needs a [Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log) row | No | **Yes** |
| Needs a human decision | No | **Yes** — [Rule 10](#rule-10--a-binding-change-is-a-human-decision-raise-it) |
| Made by the agent alone | Yes | **Never** |

The test is not the size of the diff. It is: **would a reader who followed the old line and a reader who
follows the new line build the same thing?** If not, the change is binding, however few words moved.

Because a binding change is a decision, and the [Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log)
is where a decision lives:

> Every binding decision in Talos, with the reasoning kept short. **A decision here is binding until
> changed here.** When this log and the code disagree, the log wins and the code is a bug.

So a binding change to a prose page **and** its Decision Log row are one edit, not two. A page that
states a new rule with no row behind it is a rule that is binding somewhere the log does not record,
and the log is the thing the rest of the SPEC treats as final.

Shapes that look non-binding and are not — check each by name before taking the cheap path:

- **A clarification that narrows or widens.** "Clarifying" that a rule applies only in some case is a
  new exception. Exceptions are binding; [Decision 44](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions)
  is one, and it was decided rather than clarified.
- **An anchor rename.** The text is unchanged and every link into it breaks. That is
  [Rule 8](#rule-8--a-new-page-reaches-the-sidebar-and-no-link-or-anchor-is-left-dangling), and the
  fix belongs in the same commit.
- **Tightening a hedge into an absolute, or the reverse.** "should" ↔ "must" changes what a reviewer
  may reject, so it changes behavior.
- **Adding an example.** An example that covers a case the rule does not is a new rule in example
  clothing. It is binding, and the rule is where it belongs.
- **Deleting something obsolete.** Deletion is the most binding edit there is: it removes a constraint
  someone may be relying on, and it leaves no superseding row explaining why. See
  [Rule 2](#rule-2--appended-never-rewritten).

---

## Rule 2 — Appended, never rewritten

From the [Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log) header,
verbatim:

> New decisions are appended, never rewritten. If a decision is reversed, the old row stays and a new
> row supersedes it, so the history of *why* remains readable.

So there is exactly one legal way to change a decision, and it is not editing the row:

| What you want | What you do |
| --- | --- |
| Reverse a decision | **Append** a new numbered row that supersedes it. The old row stays, untouched |
| Narrow, extend, or add a consequence to a decision | **Append** a row that says which decision it refines and how — the shape [Decision 25](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions), [37](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions), [38](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions), [44](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions), and [45](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions) already use |
| Correct a typo *inside* a decision row that changes nothing it decided | Edit it — that is [Rule 1](#rule-1--a-non-binding-fix-and-a-binding-change-are-different-acts)'s non-binding path, and it is the only edit-in-place this rule permits |
| Delete a decision that no longer applies | **Nothing is deleted.** Append the row that supersedes it and say why |

**A rewritten row is a finding regardless of whether the new wording is better.** That is the whole
point of the rule: better wording is exactly what a rewrite always looks like from inside, and the
history the log exists to keep — "the history of *why*" — is destroyed by the edit that seemed like an
improvement.

Three things a superseding row owes, taken from the rows that already do it:

1. **Its own number**, appended after the highest existing one, in the section it belongs to.
2. **The relationship, stated** — "supersedes", "refines", "extends", "completes" — and *which* decision.
   [Decision 37](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions)
   is the model: it refines 4, completes what 25 left open, and says explicitly that "**25 is not
   retired by it**", because a reader otherwise has to guess whether the older row still applies.
3. **The reasoning**, short, and the **date**.

And when the new decision spans ranks or pages, say so in the row rather than leaving the reader to
reconcile them — [Decision 47](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions)
states which of its parts sits at which rank for exactly that reason.

The corollary for prose pages: a page that a new decision changes is edited **and** the decision is
appended. Superseding in the log while leaving the page stating the old rule leaves two sources
disagreeing, and [`review-pr`](../review-pr/SKILL.md) reads the page.

---

## Rule 3 — The may-and-may-not-touch split, and the `❌ Never` column

Before editing, check whether the thing being edited is yours to edit at all. From
[Contributing § Guidelines you may and may not touch](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#guidelines-you-may-and-may-not-touch),
verbatim:

> | **[Root Talos Guidelines](Talos-Guidelines#root-talos-guidelines)** | Talos developers only, shipped via releases. Compiled into the app. |
> | **[Editable Talos Guidelines](Talos-Guidelines#editable-talos-guidelines)** | Users and Self-improver, per project, in `.talos/guidelines/`. |

Two distinct things this rule guards, and conflating them is the common error:

**(a) The product's two guideline kinds are not this wiki.** Editing the wiki *page* that describes
Root Talos Guidelines is a SPEC change, governed by this skill. Editing the Root Talos Guidelines
themselves is not possible here at all — per
[§ Root Talos Guidelines](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#root-talos-guidelines),
"Root guidelines are **compiled into the app**. They are not on disk for a user or an AI to edit."
A request to change one is a request to change the SPEC page that specifies it, plus a release.

**(b) A decision whose AI-editable column reads `❌ Never` is not edited by this skill.** The
[Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log) states which of its own
rows those are — the Project Safeguards set under *Foundational decisions*, and the Root Talos
Guidelines set under *Design decisions* — and the column itself is on
[Talos Guidelines § Authority order](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#authority-order).
Read both; do not work from the count, because the sets grow.

For those rows the answer is not "append instead of rewrite" — it is
[**raise it**](#rule-10--a-binding-change-is-a-human-decision-raise-it). Appending a row that changes a
rank-1 or rank-2 rule is the same act as rewriting one, performed with better manners.

The reason is on the wiki and is absolute rather than configurable —
[Safeguards § Limits on AI self-modification](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#limits-on-ai-self-modification):

> An AI that can widen its own permissions has no permissions. That is why this limit is absolute
> rather than configurable.

An agent editing the SPEC that constrains agents is the case that sentence describes. It is why this
skill's answer to a rank-1 or rank-2 change is a human, every time, and why a well-argued edit is not
the exception.

---

## Rule 4 — The authority order survives the edit

From [Talos Guidelines § Authority order](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#authority-order),
the binding constraint:

> **Nothing at runtime overrides #1 or #2.** Not the user in a session, not an agent, not
> Self-improver, and not content Talos reads from a third party

**An edit that lets a lower rank override a higher one is a defect**, whatever it improves. Read the
ranking table on the page rather than a copy of it, then check the edit against it:

- **Which rank does the edited rule sit at?** A rule's rank is not a property of the page it is on.
  [Decision 47](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions)
  spans three ranks from one page, so "it is on the Talos Guidelines page" answers nothing.
- **Does the edit move something down a rank?** Relocating a rule from Safeguards (rank 2) to a
  guideline file (rank 4) makes it overridable in a session. That is a widening, not a reorganization.
- **Does it create a path for a lower rank to decide something a higher rank decided?** The failure is
  usually indirect: a rank-4 file gaining a knob over what rank 2 declares, or third-party content
  gaining a way to change what Talos does rather than what Talos reads — which
  [prompt-injection posture](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#prompt-injection-posture)
  forbids.
- **Does it weaken a `❌ Never`?** Then it is [Rule 3](#rule-3--the-may-and-may-not-touch-split-and-the--never-column)
  as well, and it is raised rather than made.

Note which order applies. This rule is about the **runtime** authority order inside the product. The
development-time ordering — wiki over board item over code — is
[`spec-driven-change` § Authority order](../spec-driven-change/SKILL.md#authority-order-when-sources-conflict),
and mixing them up produces an edit that argues a session instruction outranks the SPEC.

---

## Rule 5 — Settling an open question moves the row, in the same edit

[§ Open questions](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#open-questions) is a
table of forks that are **not yet decided**:

> Decisions not yet made. Each is a real fork, not a placeholder — they are listed so they get decided
> deliberately rather than by whoever writes the code first.

So a SPEC change that answers one owes two moves **in the same commit**:

1. **Remove that row** from the open-questions table.
2. **Append it as a numbered decision** in the section it belongs to, per
   [Rule 2](#rule-2--appended-never-rewritten) — with the question, the decision, the reasoning, the
   date, and what it unblocks.

Half of that is worse than neither half. A fork that is decided and still listed as open invites the
next reader to decide it again, differently — and the row's `Blocks` column keeps pointing work at a
question that has an answer. Recent examples of the complete move:
[Decision 42](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions)
("Unblocks the board connector") and
[47](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions)
("Unblocks context assembly").

Removing the row is **not** a rewrite of a decision — the open-questions table records that no decision
exists, and appending one is what makes the row false. Rule 2 governs decided rows; this rule governs
the undecided table.

Check that table **before** starting any work, not only when editing it. Per
[`spec-driven-change` § Escalating a SPEC gap](../spec-driven-change/SKILL.md#escalating-a-spec-gap), a
change that depends on an open question is already a known gap, and the decision comes first.

---

## Rule 6 — The same change as the code, before the PR is ready

This is the step the loop names as the one that gets skipped. From
[§ Spec-driven workflow](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#spec-driven-workflow):

> ```
> 4. If the implementation reveals the spec is wrong, the SPEC is updated in the
>    same PR — never silently diverged from.
> ```

and, on what happens when the two disagree:

> Step 4 is the one that gets skipped. When the wiki and the code disagree, **the wiki wins and the
> code is a bug** — so a PR that discovers a genuinely wrong spec must fix the spec, not work around
> it. A code change that quietly contradicts the wiki is a defect even when it works.

**"Same PR" means the wiki edit is pushed before the PR is marked ready.** Not a follow-up issue, not a
TODO, not a comment in review, not "the wiki is next on my list". The `In progress` row of
[§ The dev cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle)
makes it the gate on leaving that state:

> | **In progress** | Claimed. A branch exists. RIPER-5 is running. | Implementing agent | Plan approved and executed, tests green, SPEC fixed in the same PR if it was wrong |

Three consequences:

- **The wiki edit is not the last thing.** It comes before the PR is ready, so a reviewer sees the pair.
  A PR marked ready with the wiki edit pending has left `In progress` through a gate that was not met.
- **A follow-up issue does not discharge it.** Filing one is not the legal outcome; per
  [Decision 14](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions) the
  wiki is updated in the same PR.
- **Owner bypass changes nothing here.** Per
  [Decision 46](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions) a
  bypassed merge "skips the **reviewer**, and nothing else" — the loop including step 4 still applies,
  so an unreviewed change that contradicts the wiki is the ordinary defect.

And the ordering inside step 4 matters: **fix the SPEC first, then write the code against it.** Code
written first and blessed by a wiki edit afterwards is the SPEC being made to match the implementation,
which inverts "the wiki wins and the code is a bug."

---

## Rule 7 — The wiki is a separate git repository

The wiki is not a directory in this repo. It is its own git repository:

```bash
git clone https://github.com/CalixtoTheBugHunter/talos.wiki.git /tmp/talos-wiki
# edit the page, commit, push
```

Read the page fresh before editing it, in raw Markdown, so quotes and anchors survive intact:

```bash
curl -fsSL https://raw.githubusercontent.com/wiki/CalixtoTheBugHunter/talos/Decision-Log.md
```

The commit follows
[§ Conventional Commits](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#conventional-commits)
like any other commit, with the **`spec` scope** from that section's scope list and the `docs` type,
which that section assigns to "Documentation and wiki/SPEC changes":

```
docs(spec): <what the SPEC now says>
```

That is the format the wiki's own history already uses, and it is not decoration — the same section
states the format "is the input to the release pipeline."

**Link the wiki commit from the PR body**, so the pair is reviewable together. A page's history is at
`https://github.com/CalixtoTheBugHunter/talos/wiki/<Page>/_history`, and a single revision diffs at
`https://github.com/CalixtoTheBugHunter/talos/wiki/<Page>/_compare/<sha>`. **Open the link you pasted**
and confirm it resolves to the diff — an unopenable link is the same as no link, and it is the reviewer
who discovers that.

One line in the PR body on **why the SPEC was wrong** goes with the link. The diff shows what changed;
only the author knows what the implementation revealed, and that sentence is the thing a future reader
needs.

Two notes on the mechanics, because they surprise people:

- The wiki has **no pull request and no review gate of its own.** A push is live SPEC immediately. That
  is precisely why [Rule 10](#rule-10--a-binding-change-is-a-human-decision-raise-it) puts a human in
  front of a binding change: nothing downstream will catch it.
- The repo-side branch for a change that is mostly SPEC uses the
  [`spec/<short-slug>`](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#branching)
  prefix from the branching list; a code change that also fixes the SPEC keeps its own prefix.

---

## Rule 8 — A new page reaches the sidebar, and no link or anchor is left dangling

A page nothing links to is a page nobody reads, and it becomes the copy that goes stale.

- **A new page is added to `_Sidebar.md`**, in the section it belongs to, in the same commit that
  creates it.
- **Cross-page links and anchors are updated in the same commit**, so the SPEC carries no dangling
  reference — inbound links to a renamed page, and inbound links to a renamed or removed heading.

GitHub wiki anchors are generated from heading text, so **editing a heading silently breaks every link
into it.** The link still renders; it lands at the top of the page instead of the rule. Before pushing,
find the inbound references — in the wiki, and in this repository, where every skill cites the SPEC by
anchor:

```bash
grep -rn "the-anchor-slug" /tmp/talos-wiki
grep -rn "the-anchor-slug" .claude/          # skills cite anchors; a renamed heading breaks them
```

Repointing this repository's links is part of the same change. The precedent is in the git history:
`docs(skills): repoint the ceiling references at the decided SPEC` and
`docs(spec): repoint the seven Design-System-Foundations links at the live page` are both this rule
being paid.

A dangling link is a rule that is still binding and no longer findable, which is the same failure as
deleting it — with the added cost that the reader believes they read the rule.

---

## Rule 9 — One rule, one page; everything else links

From [§ Issues are never independent of the SPEC](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#issues-are-never-independent-of-the-spec):

> An issue that restates the spec in its own words is a second source of truth, and second sources of
> truth drift. Cite and quote instead.

So the edit adds the rule to **exactly one page**, and every other page that needs it **links** there.
Copying it to a second page is the defect, and the drift is not hypothetical: the copy is the one that
does not get updated next time, and a reader cannot tell which of the two they found.

This applies in four directions, and the last two are the ones that get missed:

| Where | The rule |
| --- | --- |
| Wiki page → wiki page | Link to the owning page's anchor; do not paraphrase it into a second page |
| Wiki → this repository | A skill, a README, a code comment, or `CONTRIBUTING.md` **cites**; it never restates. `CONTRIBUTING.md` says so about itself |
| This repository → wiki | Do not "document" a repo convention onto the wiki to make it authoritative. If it is a rule, it belongs on one page and traces to a decision |
| Inside one page | A rule stated in the prose *and* in a table on the same page is two sources on one page. State it once and reference it |

When the same rule genuinely applies in two places, the fix is a link plus, where the reader needs the
words in front of them, a **verbatim quote of the owning line** — the standard the board items and
`review-pr` already hold. A quote is checkable against the source; a paraphrase is not.

---

## Rule 10 — A binding change is a human decision. Raise it.

From [Contributing § If you contribute with an AI agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills):

> A skill that hits something the SPEC does not answer raises a **SPEC gap** for a human decision and
> the [Decision Log](Decision-Log). It does not guess, and neither should you.

**A binding SPEC change is not the agent's to make alone.** Non-binding fixes per
[Rule 1](#rule-1--a-non-binding-fix-and-a-binding-change-are-different-acts) proceed. Everything else:

1. **Stop the work that depends on it.** Continue only the parts that do not. Per
   [Decision 28](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions) the
   board item moves to **`Blocked`**, which
   [§ The dev cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle)
   calls "a real destination, not a failure to try harder", and whose gate to leave is "The gap is
   decided in the [Decision Log](Decision-Log)."
2. **Raise it as a poll, stating the fork rather than the answer** — the SPEC lines that conflict or
   are silent, the pages read, the candidate answers, and what each one would change downstream. Per
   [`spec-driven-change`](../spec-driven-change/SKILL.md#escalating-a-spec-gap): "Not a recommendation
   dressed as a fact." The shape is specified by
   [Foundations: Tone § A decision goes to the user as a poll](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Tone#a-decision-goes-to-the-user-as-a-poll)
   — named and enumerated options, a recommendation marked as one and placed first, and a question
   that fits on a screen. A fork needing three paragraphs of setup has not been reduced yet, and the
   [SPEC link goes out before the poll](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Tone#every-reference-carries-its-url)
   so the human can read the page rather than the agent's account of it.
3. **Record the decision in the [Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log)**
   — appended per [Rule 2](#rule-2--appended-never-rewritten) — **before** the dependent code is
   written, and edit the prose page in the same commit.
4. **Then leave `Blocked`.** The decision existing is the gate; the item does not move back on the
   strength of an intention to record it.

The failure this prevents is specific and it is quiet: an agent that decides a fork by editing the page
has legislated with the authority of the SPEC, and the next reader cannot tell the difference between a
decision a human made and a sentence an agent wrote. Per
[`spec-driven-change`](../spec-driven-change/SKILL.md#escalating-a-spec-gap), "A guess that happens to
be right is still a process failure."

---

## The output

Structure, not prose to copy. State the classification first — everything else follows from it.

```markdown
## Classification

**<Non-binding fix | Binding change — raised, not made>**

Why: <would a reader who followed the old line build the same thing as one who follows the new line>

## What the SPEC says now, and what it should say

| Page | Line as it stands | What it should say | Why the SPEC is wrong |
| --- | --- | --- | --- |
| <Page#anchor> | <quoted verbatim from raw Markdown> | <the corrected line> | <what the implementation revealed> |

## Decision Log

<the appended row, with its number, the relationship to any decision it refines or supersedes, and the date>
<or: no row needed — non-binding fix>
<never: an edited existing row>

## Rank and authority

<which rank the edited rule sits at · that no lower rank gained a way to override a higher one>
<if the edit touches a `❌ Never` row or a Root Talos Guideline: raised, not made>

## Open questions

<row removed and appended as decision #N in the same commit · or: none touched>

## Links and anchors

<new page added to `_Sidebar.md` · inbound links and anchors repointed, in the wiki and in `.claude/`>

## Second source of truth

<the one page this rule now lives on · every other place links to it>

## The commit and the pair

<`docs(spec): …` · the wiki commit link, opened and confirmed to resolve · the one line on why the SPEC was wrong>

## Board

<Status this implies: `Blocked` until a binding change is decided · unchanged for a non-binding fix>
```

A `Classification` of non-binding with a Decision Log row in it is misclassified. So is a binding
change whose *Rank and authority* section is empty.

---

## Sibling skills

[`spec-driven-change`](../spec-driven-change/SKILL.md) runs first and owns the loop, the escalation
procedure, and the development-time authority order. [`create-issue`](../create-issue/SKILL.md) owns the
board item — including the **SPEC GAP** block an item carries instead of an assumption, and the
follow-up item a decision may need. [`review-pr`](../review-pr/SKILL.md) reviews the wiki edit this
skill produced, against this skill's own rules; its Rule 4 is the reviewer's side of
[Rule 6](#rule-6--the-same-change-as-the-code-before-the-pr-is-ready).

A SPEC change that touches a hard constraint runs the constraint skill that guards it, before the edit
rather than after: [`orchestration-boundary`](../orchestration-boundary/SKILL.md),
[`safeguards-review`](../safeguards-review/SKILL.md), [`agent-adapter`](../agent-adapter/SKILL.md),
[`gates-check`](../gates-check/SKILL.md). Editing the page a constraint lives on is the highest-leverage
way to weaken that constraint, so the guard belongs on the edit and not only on the code. The
authoritative mapping is on the wiki:
[Contributing § If you contribute with an AI agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills).

A worked example of this skill rejecting an in-place rewrite of a Decision Log row in favor of a
superseding row is in [`references/verification.md`](references/verification.md).

---

## Checklist before pushing to the wiki

- [ ] The page was fetched **fresh** as raw Markdown and read before the edit.
- [ ] The edit is classified **non-binding** or **binding**, and the classification is stated.
- [ ] A binding change was **raised to a human** and has a Decision Log row — not made alone.
- [ ] No existing decision row was rewritten, reworded, or deleted; changes are **appended** with the
      relationship and the date stated.
- [ ] Nothing edited is a [Root Talos Guideline](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#root-talos-guidelines)
      or a decision whose AI-editable column reads `❌ Never`.
- [ ] The [authority order](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#authority-order)
      still holds — no lower rank gained a path to override a higher one.
- [ ] An [open question](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#open-questions)
      this settles was **removed** from the table and appended as a numbered decision in the same commit.
- [ ] The prose page and the Decision Log agree after the edit.
- [ ] A new page is in `_Sidebar.md`; every inbound link and anchor still resolves, in the wiki **and**
      in `.claude/`.
- [ ] The rule lives on exactly one page, and every other reference is a link or a verbatim quote.
- [ ] The commit is `docs(spec): …` and the wiki link in the PR body was **opened** and resolves.
- [ ] The wiki edit is pushed **before** the PR is marked ready, with one line on why the SPEC was wrong.
- [ ] The board item is in the Status this implies — `Blocked` while a binding change is undecided.
