---
name: execute-issue
description: Implementing a board item on the Talos board. Use this whenever a ticket is to be built, picked up, or worked on — "work on issue #N", "implement this ticket", "pick up the next board item", "build #N", "start on #N", "let's do this issue", "execute #N", "take the top of the backlog", "finish the item I'm on". Also use it when resuming work already in progress, and when a failed review sends an item back to In progress. Enforces RIPER-5: the agent works in five DECLARED modes — Research, Innovate, Plan, Execute, Review — states which mode it is entering, and never acts outside that mode's mandate. Execute never starts without an approved Plan, so no file is created or edited until a numbered file-by-file plan exists and has been approved; a deviation discovered mid-Execute stops the work and returns to Plan rather than being absorbed. Research completes before the first edit and includes fetching the wiki pages the issue cites, which is how step 1 of the spec-driven loop becomes auditable rather than assumed. Moves the item through the board's Status transitions naming the owner and the gate for each, and sends a SPEC gap to Blocked for a human decision and the Decision Log instead of staying In progress and settling an open question by writing code. Runs every constraint skill whose trigger the change matches, reading the mapping from the wiki rather than hardcoding it. Review mode verifies the result against the plan and against every acceptance criterion on the issue and does not fix what it finds, because a fix is a new Plan and a new Execute — and it is a self-check, never the approval the protection rules require.
---

# Execute issue

The skill that turns a board item into a change. It is where the dev cycle is either real or
decorative: everything before it is a ticket, everything after it is a review of work already done,
and this is the only point at which *how* the work happens is still decidable.

**SPEC:** [Engineering Standards § RIPER-5](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#riper-5-how-an-agent-executes-an-issue)
· [§ The dev cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle)
· [§ A failed review returns the item to `In progress`](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#a-failed-review-returns-the-item-to-in-progress)
· [§ Review is adversarial by default](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#review-is-adversarial-by-default)
· [§ Who reviews](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#who-reviews)
· [§ Spec-driven workflow](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#spec-driven-workflow)
· [§ Git conventions](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#git-conventions)
· [§ Toolchain](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#toolchain)
· [§ Configuration is backlog work](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#configuration-is-backlog-work)
· [§ Code comments explain the non-obvious, not the history](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#code-comments-explain-the-non-obvious-not-the-history)
· [Contributing § Before you write code](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints)
· [Contributing § If you contribute with an AI agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills)
· [Decision Log § Process decisions](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions)

This skill **cites** the SPEC; it does not restate it. Rules live on the wiki pages linked here and
nowhere else — read the page, do not trust a summary in this file. Anything that looks like a rule in
this file without a link next to it is a bug in this file.

This is a **workflow skill**. Per
[Decision Log #30](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions),
a workflow skill "owns a transition in the [dev cycle](Engineering-Standards#the-dev-cycle) and is the
entry point for it" — this one owns `Ready` → `In progress` → `In review`. It **runs** the constraint
skills whose triggers the change matches; it does not re-specify what they guard.

Run [`spec-driven-change`](../spec-driven-change/SKILL.md) first. It owns the four-step loop, the
escalation procedure, and the authority order; this skill is how steps 2 and 3 of that loop are
actually carried out, and it defers to it rather than repeating it.

---

## When this fires

| Situation | Fires? |
| --- | --- |
| Building a board item, at any point in its life | **Yes** |
| Picking up the next item, or "the top of the backlog" | **Yes** — starting with [Rule 4](#rule-4--the-status-transitions-each-with-an-owner-and-a-gate) |
| Resuming an item already `In progress` | **Yes** — re-enter at the mode the work actually left off in, not at Execute |
| An item sent back by a failed review | **Yes** — [a fix is a new Plan and a new Execute](#rule-8--review-verifies-and-does-not-fix) |
| A change asked for with no board item behind it | **Yes**, and it stops immediately — see [*No item, no execution*](#no-item-no-execution) |
| Authoring, rewriting, or closing an item | No — [`create-issue`](../create-issue/SKILL.md) |
| Reviewing a PR, or asking whether it can merge | No — [`review-pr`](../review-pr/SKILL.md) |
| Changing what the wiki says | No — [`update-spec`](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills) |

Phrasings that fire it: "work on issue #N", "implement this ticket", "pick up the next board item",
"build #N", "start on #N", "let's do this issue", "execute #N", "can you knock this out", "finish what
you were doing on #N".

**A one-line change is not exempt.** The mode discipline is cheapest on a small item and it is the
small item where it gets skipped, because the work looks too obvious to plan. An obvious change is one
whose Plan takes thirty seconds to write, not one that needs no Plan.

Configuration is not exempt either. Skills, CI workflows, security configuration, and git protection
are [backlog work](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#configuration-is-backlog-work)
like everything else, so they are executed like everything else.

---

## Rule 1 — Five declared modes, and the mode is stated on entering it

The mode table is the SPEC. Quoted verbatim from
[§ RIPER-5](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#riper-5-how-an-agent-executes-an-issue):

> | Mode | Mandate | Forbidden in this mode |
> | --- | --- | --- |
> | **Research** | Read the SPEC pages the issue cites, the issue's own criteria, and the existing code | Proposing anything, or writing anything |
> | **Innovate** | Surface the options and their trade-offs against the SPEC | Choosing one, or writing code |
> | **Plan** | One numbered, file-by-file plan, each step traced to a SPEC line or an acceptance criterion | Writing code |
> | **Execute** | Implement the approved plan exactly, step by step | Any deviation, however small, and any unrequested improvement |
> | **Review** | Verify the result against the plan, the acceptance criteria, and every constraint page touched | Fixing what it finds — a fix is a new Plan and a new Execute |

And the requirement that makes it checkable, same section:

> An agent implementing a board item works in **five declared modes** and never acts outside the
> mandate of the mode it is in. It states which mode it is entering.

**Declaring the mode is not ceremony — it is the only thing that makes the mandate enforceable.** An
undeclared mode cannot be exceeded, because nobody can say which mandate was in force. So write the
mode before the work in it, in a form a reader can see:

```markdown
**Mode: RESEARCH** — <what is being read, and why that set>
```

Two failures the declaration exists to catch, and both look like productivity in the moment:

- **Collapsing Plan into Execute.** The plan arrives alongside the code it describes, so it is a
  description rather than a proposal. [Decision 27](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions)
  names the cost: "nobody reviewed the approach while it was still reversible."
- **Declaring a mode and then acting outside it.** A stated `Mode: PLAN` followed by an edit is worse
  than no declaration, because the label asserts a discipline the work did not follow.

The modes run in order. Innovate may be brief when the SPEC leaves one legal approach — and "brief"
means the options were considered and the constraint that eliminated them named, not that the section
was skipped.

---

## Rule 2 — Research completes before the first edit, and includes the pages the issue cites

From the same section, and this is a rule about *completeness*, not about effort:

> Research is not optional and not partial. Per the [loop](#spec-driven-workflow), step 1 happens
> before the first edit; RIPER-5 is how that step is made auditable rather than assumed.

**Hard stop.** No file is created or edited until Research is done. Three things are read, and the
first is the one that gets substituted with memory:

1. **Every wiki page the issue cites**, fetched **fresh**. A page read in an earlier session may have
   changed, and the issue's quoted lines may now be paraphrases of it.
2. **The issue's own criteria**, from the issue — not from the request that pointed at it. They are
   the definition of done, and [`create-issue`](../create-issue/SKILL.md) wrote them to be checkable.
3. **The existing code**, including whatever already does the thing nearly.

```bash
gh issue view <N> --repo CalixtoTheBugHunter/talos
curl -fsSL https://raw.githubusercontent.com/wiki/CalixtoTheBugHunter/talos/Engineering-Standards.md
```

Substitute the page name from the wiki URL. When the change spans pages, or you need to grep the SPEC,
[`spec-driven-change` § Step 0](../spec-driven-change/SKILL.md#step-0--fetch-the-spec-before-writing-code)
has the whole-wiki clone.

Then add every page the change could **violate**, in the order
[Contributing § Before you write code](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints)
lists them — that order is "how often they get violated by accident", so it is the reading order too.
The issue's Spec Page is where the change comes *from*; that list is what it could break on the way.

**Research produces no proposal.** State what was read and what it says. The moment a sentence starts
"so we should…", the mode has changed and has not been declared.

---

## Rule 3 — Execute never starts without an approved Plan

This is the rule the whole skill exists for. Verbatim:

> **Execute never starts without an approved Plan, and a deviation discovered mid-Execute stops the
> work and returns to Plan.**

**Hard stop, and it is a blocking one.** Before the first edit there is a numbered, file-by-file plan,
and it has been approved. Not written — approved. The Plan mode's own mandate states its shape:
"One numbered, file-by-file plan, each step traced to a SPEC line or an acceptance criterion."

So each step carries three things, and a step missing the third is not a plan step:

| Every plan step names | Why |
| --- | --- |
| **The file** it touches, by path | A plan that names no files cannot be checked against the diff in Review |
| **What changes** in it | So the reviewer of the *plan* can object before the work is expensive to undo |
| **The SPEC line or acceptance criterion** it serves | The traceability the mandate requires; a step serving neither is scope nobody asked for |

**A deviation stops the work.** Mid-Execute, anything the plan did not say — a file that has to change
too, an approach that does not work, a criterion the plan misread — ends Execute and returns to Plan.
It is not absorbed, not noted for later, and not "obviously fine". The revised plan is stated as a
plan, in `Mode: PLAN`, before Execute resumes.

Two shapes of absorbed deviation to name, because both feel like diligence:

- **The adjacent fix.** A bug spotted in a file the plan opened for another reason. Real, and still a
  deviation — Execute forbids "any unrequested improvement". Report it; a fix is its own item.
- **The small extra file.** The plan named three files and the change needs a fourth. That is the
  discovery the return-to-Plan rule is for, not a rounding error.

Approval is a human act. Where a session has granted standing approval for an item's plan, that is the
approval — recorded, and scoped to the item it was given for. An agent does not approve its own plan by
finding it reasonable, for the same reason
[an agent's review is not the approval](#rule-8--review-verifies-and-does-not-fix).

**A comment written during Execute follows [§ Code comments explain the non-obvious, not the
history](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#code-comments-explain-the-non-obvious-not-the-history):**
it states a hidden constraint or an invariant, never the issue it closes, the thread that produced it,
or a TODO pointing at a later PR — that belongs in the commit and the PR body, not the file.

---

## Rule 4 — The Status transitions, each with an owner and a gate

The board's Status field "is a state machine, not a set of labels", and the owners and gates are the
[dev cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle)
table — read it there. The transitions **this skill** drives, with the gate quoted from that table:

| Transition | Owner | Gate to make it |
| --- | --- | --- |
| `Backlog` → `Ready` | **Human** | Not this skill's move. Scheduling is a human's; per that table the gate is "Spec Page and DoD filled, binding lines quoted, INVEST holds" |
| `Ready` → `In progress` | Implementing agent | "Nothing in it is still a SPEC gap" — so check the item and [§ Open questions](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#open-questions) before claiming it |
| `In progress` → `In review` | Implementing agent | "Plan approved and executed, tests green, SPEC fixed in the same PR if it was wrong" |
| any active state → `Blocked` | Implementing agent | A SPEC gap or an unmet dependency — see [Rule 5](#rule-5--a-spec-gap-moves-the-item-to-blocked-and-goes-to-a-human) |
| `In review` → `In progress` | Reviewer's findings | The one backwards edge, and [`review-pr`](../review-pr/SKILL.md) owns it. This skill is what runs *after* it |
| `In review` → `Done` | — | Not this skill. [`create-issue`](../create-issue/SKILL.md) closes the item criterion by criterion |

**Move the item when the thing becomes true, not at the end.** A board read halfway through the work
is the read that matters, and per that section a Status meaning "roughly how the author felt last week"
is "a board nobody consults, and traceability decays into fields nobody trusts."

**Re-read before you write.** Per [Decision 42](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions),
a write that changes existing state compares actual against expected first and never overwrites a
change it did not read. If the item is not in the state you expected — someone moved it — stop and
show both states rather than moving it anyway.

```bash
gh project item-list 5 --owner CalixtoTheBugHunter --format json --limit 300
gh project field-list 5 --owner CalixtoTheBugHunter --format json
gh project item-edit --project-id <project> --id <item> --field-id <Status> --single-select-option-id <option>
```

Discover the IDs rather than pasting them from anywhere; a field ID copied into a file is the stale
duplication this skill avoids everywhere else.

Only one backwards edge exists. Per [Decision 44](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions),
"A named exception is enforceable; an unnamed one becomes a habit of moving items backwards whenever
it is convenient" — so do not invent a second one.

---

## Rule 5 — A SPEC gap moves the item to `Blocked` and goes to a human

The gap is the case where continuing is the failure. From
[the dev cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle):

> **Blocked is a real destination, not a failure to try harder.** An agent that hits a SPEC gap moves
> the item to Blocked and raises the gap; it does not stay In progress and decide the open question by
> writing code.

[`spec-driven-change` § Escalating a SPEC gap](../spec-driven-change/SKILL.md#escalating-a-spec-gap)
owns the procedure — what to state, who decides, how it is recorded. What is specific to executing an
item:

- **The gap can surface in any mode, and it stops that mode.** Found in Research, the Plan is never
  written; found mid-Execute it is a deviation *and* a gap, so the work stops rather than returning to
  Plan.
- **`Blocked`, not a slower `In progress`.** Its gate to leave is that "The gap is decided in the
  [Decision Log](Decision-Log)", which is a human's act.
- **Continue what does not depend on it.** Steps of the plan that stand independently of the gap are
  still executable; say which ones were left.
- **Check [§ Open questions](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#open-questions) first.**
  A gap already listed there is known, and an item depending on one was never `Ready`.

A plausible-looking answer written into code is the specific harm here. Per
[Contributing](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills):

> A skill that hits something the SPEC does not answer raises a **SPEC gap** for a human decision and
> the [Decision Log](Decision-Log). It does not guess, and neither should you.

An implementer's guess is the hardest kind to find later, because it arrives as working code with tests
around it.

---

## Rule 6 — Run the constraint skills the change matches

That is what a workflow skill is for, and the mapping lives on the wiki so it cannot drift here:
[Contributing § If you contribute with an AI agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills).
Read that table and run every skill whose trigger the change matches — the four are
[`orchestration-boundary`](../orchestration-boundary/SKILL.md),
[`safeguards-review`](../safeguards-review/SKILL.md),
[`agent-adapter`](../agent-adapter/SKILL.md), and
[`gates-check`](../gates-check/SKILL.md), and each states its own trigger surface.

**Run them in Research and again in Review, and they are read before the Plan is written.** A
constraint skill read after Execute is a review of a decision already made; read before Plan, it is
what makes one option illegal and shortens the plan.

Prefer over-firing to under-firing: a constraint skill run needlessly costs a read, while one not run
is a hard constraint nobody checked. Per
[Decision 11](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions)
`spec-guard` exists because the boundary rule is the easiest to violate accidentally — so a green
`spec-guard` is a grep having passed, not the boundary having been reviewed.

---

## Rule 7 — Tests assert the SPEC's stated behavior

Step 3 of the [loop](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#spec-driven-workflow)
is that the PR's "tests assert the spec's stated behavior". The toolchain, the required checks, and
what the suite may depend on are on the wiki:
[§ Toolchain](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#toolchain),
[§ The suite installs nothing](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-suite-installs-nothing),
[§ CI pipeline order](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order).
Read them there; what belongs to executing an item is only this:

- **Write the test against the SPEC line, not against the code you just wrote.** A test written by
  reading the implementation records what the implementation does. Per § Toolchain, Swift Testing was
  chosen so a test "keeps a test readable as a statement of the spec it verifies" — so cite or quote
  the SPEC line in the test where practical.
- **Ask what regression each assertion would catch, and be able to name it.** An assertion that would
  survive the behavior being wrong is not a test of that behavior.
- **`In progress` does not end with a red or missing check.** Its gate includes "tests green", and per
  § CI pipeline order every stage is required — so a stage that did not run has not passed.

[`review-pr` Rule 2](../review-pr/SKILL.md#rule-2--the-tests-fail-if-the-behavior-regresses) lists the
patterns that verify nothing. Read it while writing the tests, not after a reviewer cites it.

---

## Rule 8 — Review verifies, and does not fix

The last mode has the tightest mandate, quoted from the RIPER-5 table:

> | **Review** | Verify the result against the plan, the acceptance criteria, and every constraint page touched | Fixing what it finds — a fix is a new Plan and a new Execute |

So Review produces three lists, and **every** acceptance criterion on the issue gets a row — including
the ones the work never mentioned, which are the ones most likely to be missing:

| Verified against | Evidence |
| --- | --- |
| **The plan** | Each numbered step, and where in the diff it landed. A step with no diff behind it was not executed |
| **Every acceptance criterion on the issue** | The file and line, test name, or command output that meets it — read from the issue, not from your own summary of it |
| **Every constraint page touched** | In [Contributing's order](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints), with the constraint skill from Rule 6 run again |

**A finding is not fixed in Review.** It ends the mode: state it, then re-enter `Mode: PLAN` for the
fix. Fixing inside Review is how a plan silently grows the work nobody approved, and it destroys the
one thing Review produces — an honest list of what the plan did not achieve.

**This review is a self-check and not the gate.** Per
[§ Who reviews](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#who-reviews)
and [Decision 43](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions),
an agent's review "is a self-check, not the [1 approval](#protection-rules-on-main) the protection
rules require", and this one is narrower still: it is the *author* checking its own work against its
own plan. The adversarial pass is [`review-pr`](../review-pr/SKILL.md), which tries to refute the
change — a different act, done against the diff.

**And it does not close the item.** Per
[Decision 40](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions),
[`create-issue`](../create-issue/SKILL.md) closes it criterion by criterion against the list it wrote.

---

## Opening the PR

Branch prefixes, the commit format, the scope vocabulary, and everything required on `main` are on the
wiki and are not copied here:
[§ Branching](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#branching)
· [§ Conventional Commits](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#conventional-commits)
· [§ Protection rules on `main`](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#protection-rules-on-main).
Two things to get from the item rather than from plausibility: the **branch prefix** matching the kind
of work, and the commit **scope**, which comes from the board's **Area** field on the item you are
building.

What the PR body owes is step 3 of the loop, and
[`spec-driven-change` § Step 3](../spec-driven-change/SKILL.md#step-3--the-pr-references-both) owns the
list: `Closes #<issue>`, each wiki page linked with its **binding line quoted verbatim**, the DoD
criterion advanced or the stated justification for none, and — if the SPEC changed — the wiki diff and
one line on why the SPEC was wrong.

Quote from the raw Markdown so the quote is verbatim rather than nearly:

```bash
curl -fsSL https://raw.githubusercontent.com/wiki/CalixtoTheBugHunter/talos/<Page>.md
```

Then move the item to `In review`. Per the dev cycle that state asserts "PR open, referencing the item,
the wiki page, and the DoD criterion" — so the move and the body are one act, not a move followed by an
intention to fill the body in.

---

## Mode output templates

Structure, not prose to copy. Everything in angle brackets comes from the item, the SPEC, or the diff.

```markdown
**Mode: RESEARCH**

Wiki pages read (fetched fresh): <page § section — what it binds here>
Constraint pages that could be violated: <Contributing's ordered list, filtered to this change>
Issue criteria: <count, read from the issue>
Existing code: <what already does this, or nearly>
Traceability: <board item · Spec Page · DoD criterion or the stated justification>

**Mode: INNOVATE**

<option — trade-off against a SPEC line>
<option — trade-off against a SPEC line>
<what the SPEC makes illegal, and which option that eliminates>

**Mode: PLAN**

1. `<path>` — <what changes> → <SPEC line or AC-n>
2. …

<the approval this needs, and from whom>

**Mode: EXECUTE**

<step N done — nothing outside the plan>
<deviation found → stop, return to PLAN with the revised plan>

**Mode: REVIEW**

| Plan step | Where it landed |
| --- | --- |
| # | Acceptance criterion | Evidence | Verdict |
| Constraint page | Skill run | Result |

Step 4 of the loop: <does the change now contradict any wiki page — and if so, was the wiki fixed here>
Findings: <each one, and the new PLAN it requires — not fixed in this mode>
Board: <Status this implies>
This is a self-check, not the 1 approval the protection rules require.
```

A `Mode: EXECUTE` block with no preceding approved `Mode: PLAN` is the failure this skill exists to
prevent, and so is a `Mode: REVIEW` whose criteria table has fewer rows than the issue has criteria.

---

## No item, no execution

A change with no board item behind it does not get built here. Per
[§ Configuration is backlog work](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#configuration-is-backlog-work)
and [`spec-driven-change` § Step 1](../spec-driven-change/SKILL.md#step-1--trace-the-change-to-three-things),
the item, the Spec Page, and the DoD criterion are named before the work starts — and a missing one is
a stop, not a thing to add afterwards.

So when the request names no item: say so, and offer to author one with
[`create-issue`](../create-issue/SKILL.md). Do not build it and file the ticket after — an item written
to match a finished change is a description of the work, not a specification of it, and its criteria
will be met by whatever the diff happens to do.

---

## SPEC gaps this skill knows about

Open questions live in the [Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#open-questions);
check them before claiming an item, because an item depending on one is `Blocked` rather than `Ready`.

| Gap | Current handling |
| --- | --- |
| **Who approves a Plan, and what form the approval takes.** [§ RIPER-5](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#riper-5-how-an-agent-executes-an-issue) requires an approved Plan and names no approver | Ask. The section's stated purpose is that "no human ever reviewed the decision while it was still a decision", so the approval is a human's. This skill does not self-approve, and it does not treat silence as approval. |
| **Whether `Ready` → `In progress` needs a human's assignment.** The dev cycle names the implementing agent as the mover and says nothing about claiming | Claim it and say so in the same breath. Do not reassign an item already claimed by someone else. |
| **What Innovate owes when the SPEC leaves exactly one legal approach** | Name the options considered and the constraint that eliminated each. Brevity is legal; an absent Innovate is not. |

A gap discovered while executing goes to a human and the Decision Log — it does not get a row here and
a guess in the code.

---

## Sibling skills

[`spec-driven-change`](../spec-driven-change/SKILL.md) runs first and owns the loop, the escalation
procedure, and the authority order. [`create-issue`](../create-issue/SKILL.md) owns the item's criteria
at both ends — authoring them, and closing against them.
[`review-pr`](../review-pr/SKILL.md) owns the adversarial pass this skill's Review mode is not. The full
skill-to-constraint mapping is on the wiki so it cannot drift here:
[Contributing § If you contribute with an AI agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills).

Per Rule 6, this skill runs the constraint skill whose trigger the **change** matches:
[`orchestration-boundary`](../orchestration-boundary/SKILL.md) on networking, adapters, MCP, or
credentials; [`safeguards-review`](../safeguards-review/SKILL.md) on tiers, the gate, allowlists, or
approval UI; [`agent-adapter`](../agent-adapter/SKILL.md) on adapter work;
[`gates-check`](../gates-check/SKILL.md) on UI, memory, launch, or token overhead.

A worked example of this skill refusing to edit a file before a Plan is approved is in
[`references/verification.md`](references/verification.md).

---

## Checklist, by mode

Research:

- [ ] Every wiki page the issue cites was fetched **fresh** and read.
- [ ] The constraint pages the change could violate were read in
      [Contributing's order](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints).
- [ ] The criteria were read from the **issue**, and the board item, Spec Page, and DoD criterion are
      all named — or the missing DoD is explicitly justified.
- [ ] Nothing was proposed and nothing was written.

Innovate and Plan:

- [ ] The options and their trade-offs against the SPEC were stated before one was chosen.
- [ ] The plan is numbered and file-by-file, and every step traces to a SPEC line or a criterion.
- [ ] No file was created or edited while planning.
- [ ] The plan was **approved** before Execute began.

Execute:

- [ ] Every edit is a step of the approved plan, and no step went beyond it.
- [ ] No adjacent bug was fixed and no improvement was added unrequested.
- [ ] Any deviation stopped the work and returned to Plan, with the revised plan stated.
- [ ] No SPEC rule was paraphrased into code, a comment, a README, or a repo doc — it is a link.
- [ ] No comment narrates a thread, an issue/PR reference, or superseded history instead of a
      hidden constraint or invariant.

Review:

- [ ] Every plan step has a location in the diff, and every acceptance criterion has a row.
- [ ] Each constraint skill matching the change was run again, and the result stated.
- [ ] Step 4 was checked against the pages the **change** touches, not only the ones the issue cites —
      and the wiki was fixed in this PR if they now disagree.
- [ ] Nothing found in Review was fixed in Review.
- [ ] The review says it is a self-check and not the required approval.

Board and PR:

- [ ] The item's Status was moved when each thing became true, after re-reading its actual state.
- [ ] Any SPEC gap sent the item to `Blocked` and went to a human and the Decision Log.
- [ ] The branch prefix and the commit scope come from the item's kind and its **Area** field.
- [ ] The PR body carries `Closes #<N>`, each wiki page linked with its line quoted verbatim, and the
      DoD criterion or its justification.
