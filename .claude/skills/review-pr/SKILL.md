---
name: review-pr
description: Reviewing a pull request against the SPEC. Use this whenever a PR is to be reviewed, approved, rejected, or assessed as mergeable — "review this PR", "review #N", "is this mergeable", "look over this diff", "can this merge", "what do you think of this change", "approve this", "LGTM?", "check my PR before I ask for review". Also use it before merging anything, and when a PR is moved out of the In review status. Enforces the adversarial posture: the reviewer tries to REFUTE the change rather than confirm it, and an approval is a claim that someone tried to break it and could not. Verifies every acceptance criterion on the linked issue against the DIFF and never against the PR description, because a checked box with no code behind it is the defect; verifies the tests assert the SPEC's stated behavior and would FAIL if that behavior regressed; re-reads every constraint page the change touches in the order Contributing lists them; enforces step 4 of the spec-driven loop, so a PR whose code and wiki disagree is not mergeable unless the wiki was fixed in the same PR; checks the PR body carries the issue reference, each wiki page linked with its binding line quoted verbatim, and the DoD criterion or an explicit justification; requires the git and CI conventions by link; reports every finding rather than silently fixing it; and sends a SPEC gap found in review to a human and the Decision Log rather than settling it with the reviewer's judgement. States that an agent's review is a self-check and never the 1 approval the protection rules require; moves an item with findings against it back to In progress, the one backwards edge in the dev cycle; and permits approving a partly satisfying PR only when every unmet criterion is named and carries a filed follow-up item, never for a hard constraint, a release gate, or a Safeguards behavior.
---

# Review PR

The last gate before `main`, and the only one that reads the diff against the SPEC. Every check above
it is mechanical, so a PR that compiles, passes its own tests, and quietly implements something the
wiki does not say reaches `main` with nothing else positioned to stop it.

**SPEC:** [Engineering Standards § Review is adversarial by default](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#review-is-adversarial-by-default)
· [§ The dev cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle)
· [§ Spec-driven workflow](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#spec-driven-workflow)
· [§ Git conventions](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#git-conventions)
· [§ CI pipeline order](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order)
· [§ RIPER-5](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#riper-5-how-an-agent-executes-an-issue)
· [§ Closing an item](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#closing-an-item-is-the-authoring-gate-run-backwards)
· [Contributing § Before you write code](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints)
· [Contributing § If you contribute with an AI agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills)
· [Decision Log § Process decisions](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions)
· [Decision Log § Engineering decisions](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions)

This skill **cites** the SPEC; it does not restate it. Rules live on the wiki pages linked here and
nowhere else — read the page, do not trust a summary in this file. Anything that looks like a rule in
this file without a link next to it is a bug in this file.

This is a **workflow skill**. Per
[Decision Log #30](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions),
a workflow skill "owns a transition in the [dev cycle](Engineering-Standards#the-dev-cycle) and is the
entry point for it" — this one owns the exit from `In review`, whose gate is *adversarial review
passed*. It **runs** the constraint skills whose triggers the change matches; it does not re-specify
what they guard.

Run [`spec-driven-change`](../spec-driven-change/SKILL.md) first. It owns the four-step loop, the
escalation procedure, and the authority order; this skill owns step 3 of that loop as seen from the
reviewer's side, and defers to it rather than repeating it.

---

## The posture

From [§ Review is adversarial by default](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#review-is-adversarial-by-default):

> A reviewer's job is to try to **refute** the PR, not to confirm it.

and:

> An approving review is a claim that someone tried to break the change and could not. A review that
> only reads the PR description checks the author's summary, not the author's work — and the summary
> is written by the party with the least incentive to find the flaw.

So the question this skill answers is never "does this look reasonable?" It is **"what would make
this wrong, and can I demonstrate it?"** Three consequences worth stating because they are what the
posture costs in practice:

- **The default is not-approved.** Approval is earned by a failed attempt to break the change, so a
  change nobody managed to attack has not passed — it has not been reviewed.
- **Reading the description is not reviewing.** It is reading a claim written by the author. Every
  claim in it is a hypothesis to test against the diff, and the ones easiest to believe are the ones
  worth testing first.
- **"I could not find anything" is only an approval if you looked.** State what you tried to break
  and how. A review that lists no attempted refutation is indistinguishable from a skim.

[Decision Log #29](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions)
settles what a review is for, and this skill is that decision made runnable.

---

## When this fires

| Situation | Fires? |
| --- | --- |
| Reviewing a PR, at any point in its life | **Yes** |
| Assessing whether something can merge, or approving it | **Yes** — an approval is the claim this skill qualifies |
| Rejecting a PR, or requesting changes | **Yes** — the finding has to be evidenced against the diff |
| Self-checking your own PR before asking for review | **Yes**, with [*Who reviews*](#who-reviews-and-what-this-skill-is-not) read first |
| Moving an item out of `In review` | **Yes** — that is the transition this skill owns |
| Implementing a board item | No — [`execute-issue`](../execute-issue/SKILL.md) |
| Authoring, rewriting, or closing an item | No — [`create-issue`](../create-issue/SKILL.md) |
| Changing what the wiki says | No — [`update-spec`](../update-spec/SKILL.md) |

Phrasings that fire it: "review #N", "review this PR", "is this mergeable", "can this merge", "look
over this diff", "what do you think of this change", "approve this", "LGTM?", "any objections",
"check this before I merge".

A PR touching only configuration is not exempt. Skills, CI workflows, security configuration, and git
protection are
[backlog work](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#configuration-is-backlog-work)
like everything else, so they are reviewed like everything else.

---

## Rule 1 — Every acceptance criterion, met in the diff

From [§ Review is adversarial by default](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#review-is-adversarial-by-default),
the first of the three things checked by inspection:

> 1. **Every acceptance criterion** on the issue — met in the diff, not claimed in the PR body. A
>    checked box with no code behind it is the defect.

**Every** means every one, in the order the issue authored them, including the ones the PR body does
not mention. Read the criteria from the issue itself rather than from the PR's restatement of them:

```bash
gh pr view <N> --repo CalixtoTheBugHunter/talos --json title,body,headRefName,files,statusCheckRollup
gh pr diff <N> --repo CalixtoTheBugHunter/talos
gh issue view <M> --repo CalixtoTheBugHunter/talos   # the issue the PR closes — its criteria are the list
```

Produce one row per criterion, and the middle column is a location in the diff:

```markdown
| # | Criterion | Where in the diff | Verdict |
| --- | --- | --- | --- |
| 1 | <the criterion, as the issue worded it> | <file:line, hunk, or test name> | met / **NOT MET** / unevidenced |
```

**A criterion whose only evidence is the PR body is not met.** That is the defect the SPEC names, and
it is the specific failure this rule exists to catch: the box is checked, the sentence in the
description is true-sounding, and the diff does something adjacent to what the criterion asked for.
Three shapes of it to look for by name:

- **Adjacent, not equal.** The criterion asks for behavior X and the diff implements X′ — narrower,
  or under a condition the criterion did not carry. Compare the criterion's words to the diff's
  words, not to the description's words.
- **Asserted in prose.** The criterion is met by a sentence in the PR body, a comment, or a doc line
  claiming the behavior, with no code or test behind it.
- **Silently dropped.** The criterion appears in neither the diff nor the description. A criterion the
  PR body never mentions is the one most likely to be missing, because nothing drew attention to it.

**An unmet criterion may be deferred, and deferring has a price the reviewer pays up front.** Per
[§ Approving a partial change](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#approving-a-partial-change):

> **A PR that meets most of its criteria may be approved, provided the reviewer names every unmet
> criterion and links a follow-up board item for each.** The link is the condition and not a courtesy: an
> unmet criterion with no item behind it is simply unmet

So a partial approval is legal only with **every** unmet criterion named and **each** carrying a
follow-up item — authored by [`create-issue`](../create-issue/SKILL.md) like any item, before the
approval, not promised after it. Three limits, and the third is the one to check hardest:

- **The item does not reach `Done`.** A merged PR with a deferred criterion leaves its item open, per
  the same section and [Decision 40](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions).
- **Deferring is not striking.** A reviewer defers; only the item's author strikes, with a reason
  recorded on the item. Report a criterion you believe obsolete — do not remove it.
- **Some criteria are never deferrable.** Quoted from the same section:

  > A criterion carrying a
  > [hard constraint](Contributing#before-you-write-code-read-the-constraints), a release gate
  > ([#9 and #10](MVP-Definition-of-Done#notes-on-the-harder-criteria)), or a
  > [Safeguards](Safeguards-and-Autonomy) behavior is met in the PR or the PR does not merge.

  Check the criterion's *subject*, not its size. A one-line change to an allowlist or a VoiceOver label
  is small and still not deferrable.

The SPEC states the cost of this path plainly, and a reviewer using it should be able to say why it is
worth paying here: it "is the mechanism by which 'we'll do it in the next PR' becomes never, and it puts
a scope decision in the reviewer's hands."

---

## Rule 2 — The tests fail if the behavior regresses

The second thing checked by inspection, verbatim:

> 2. **The tests** — they assert the SPEC's *stated behavior*, and they fail if the behavior regresses.
>    A test that passes against both the specified and the unspecified behavior verifies nothing.

Two distinct checks, and the second is the one that gets skipped:

**(a) The test asserts the SPEC's stated behavior.** Not the implementation's behavior. A test written
by reading the code it tests records what the code does, which is exactly the thing under review. Per
[§ Toolchain](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#toolchain),
Swift Testing was chosen so a test "keeps a test readable as a statement of the spec it verifies" —
so a test whose name and body do not read as a statement of a SPEC line is a finding, not a style
note.

**(b) The test would fail if that behavior regressed.** Establish this by inspection, per assertion:
ask what change to the production code the assertion would catch, and name it. If the answer is
"none" — or "only a change nobody would make" — the assertion verifies nothing.

Patterns that pass against both the specified and the unspecified behavior, and are therefore
findings:

| Pattern | Why it verifies nothing |
| --- | --- |
| Asserts a value the code would produce either way | True before the change and after it regresses |
| Asserts only "did not throw" or "is not nil" for behavior specified as a value | The specified value is untested |
| Tests the happy path of a rule whose content is the denial | Per [DoD #5](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#notes-on-the-harder-criteria), "a denial handled cleanly" is the real test — "Anyone can build an automator that works when you say yes" |
| Asserts an error occurred without asserting which one | A different failure, including the wrong one, passes |
| Mirrors the implementation's own steps | Regresses with the code it tests, in the same direction |
| No test at all for a criterion, with the PR calling it untestable | The SPEC has the reviewer check criteria "by inspection rather than by trusting the description" ([§ Review is adversarial by default](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#review-is-adversarial-by-default)) — so if a criterion carries no test, name what was inspected and where |

Also check what the suite is allowed to need. Per
[§ The suite installs nothing](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-suite-installs-nothing)
and [Decision 34](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions),
a test requiring an installed CLI, a real credential, or the network is a finding — "a skipped test is
indistinguishable from a passing one on a green run" — and a fixture holding a token or key "is a
secret in git rather than a test asset."

---

## Rule 3 — Every constraint page the change touches, in Contributing's order

The third thing checked by inspection, verbatim:

> 3. **Every constraint page the change touches**, in the order
>    [Contributing](Contributing#before-you-write-code-read-the-constraints) lists them, plus the
>    [spec-driven loop's step 4](#spec-driven-workflow) — if code and wiki now disagree, the wiki was
>    fixed in this PR or the PR is not mergeable.

The list and its order are on the wiki at
[Contributing § Before you write code](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints);
**read it there**, in that order, because the order is "how often they get violated by accident" and
reading it in any other order spends the most attention on the least-violated rule. What the page says
about the whole list is the standard the review applies:

> Talos has **hard constraints** that are rejected rather than negotiated. A PR that violates one
> will be closed regardless of code quality.

"…closed regardless of code quality" is the operative clause. A well-built violation is still closed,
so quality of implementation is never the counterargument to a constraint finding.

**Run the constraint skill whose trigger the diff matches** — that is what a workflow skill is for.
The mapping lives on the wiki so it cannot drift here:
[Contributing § If you contribute with an AI agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills).
The four are [`orchestration-boundary`](../orchestration-boundary/SKILL.md),
[`safeguards-review`](../safeguards-review/SKILL.md),
[`agent-adapter`](../agent-adapter/SKILL.md), and
[`gates-check`](../gates-check/SKILL.md); each states its own trigger surface, and the trigger is the
**diff**, not the PR's account of the diff.

Match on the files and lines actually changed, and prefer over-firing to under-firing: a constraint
skill run needlessly costs a read, while one not run is a hard constraint nobody checked. Per
[Decision 11](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions),
`spec-guard` exists because the boundary rule "is the easiest to violate accidentally" — so a green
`spec-guard` is a grep having passed, not the boundary having been reviewed.

---

## Rule 4 — Step 4 of the loop, or the PR is not mergeable

This is the step the loop itself flags as the one that gets skipped, and the reviewer is the last
party able to enforce it. From
[§ Spec-driven workflow](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#spec-driven-workflow):

> 4. If the implementation reveals the spec is wrong, the SPEC is updated in the
>    same PR — never silently diverged from.

and, on what happens when they disagree:

> Step 4 is the one that gets skipped. When the wiki and the code disagree, **the wiki wins and the
> code is a bug** — so a PR that discovers a genuinely wrong spec must fix the spec, not work around
> it. A code change that quietly contradicts the wiki is a defect even when it works.

So for a PR that changes described behavior there are exactly two mergeable outcomes, and the third is
the finding:

| What the diff does | Mergeable? |
| --- | --- |
| Implements what the wiki says | ✅ |
| Contradicts the wiki, **and** the wiki was fixed in this PR with the change linked from the body | ✅ — and if the correction is binding, it is a [decision](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log), not the author's call |
| Contradicts the wiki, with a follow-up issue, a TODO, or a promise in review | ❌ **Not mergeable** — [Decision 14](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions) requires the same PR |

**"Behavior described in this wiki" is broader than it looks.** Check the diff against the pages the
issue cites *and* the pages the diff touches — a change can be faithful to its own Spec Page and
contradict a different one. The reviewer's question is not "did the author read the SPEC?" but "does
this diff now disagree with any page of it?"

A wiki edit shipped alongside the PR is reviewed too, against
[Contributing § Guidelines you may and may not touch](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#guidelines-you-may-and-may-not-touch)
and the Decision Log's own rule that "New decisions are appended, never rewritten." A binding change
made by rewriting a row is a finding regardless of whether the new wording is better.

---

## Rule 5 — What the PR body owes

The `In review` row of
[the dev cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle)
states what is true while an item sits there:

> | **In review** | PR open, referencing the item, the wiki page, and the DoD criterion | Reviewer | Adversarial review passed — see below. Findings against it send the item [back to In progress](#a-failed-review-returns-the-item-to-in-progress) |

So three things are checked in the body, and each has a failure mode that a reader in a hurry accepts:

| The body carries | Verified how | Finding if |
| --- | --- | --- |
| **The issue reference** — `Closes #<N>` | The issue exists, is on the board, and is the item this diff implements | It closes an issue whose criteria the diff does not address, or references none |
| **Each wiki page, linked, with the binding line quoted verbatim** | Diff the quote against the page's raw Markdown | A word changed, a clause dropped, emphasis moved, or a section summarized instead of a line quoted |
| **The DoD criterion advanced, or the justification for advancing none** | The criterion is a numbered row in [MVP DoD](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#checklist); a justification is stated, not blank | Blank, or "N/A" with no reason |

Verbatim is checkable, so check it rather than eyeballing it:

```bash
curl -fsSL https://raw.githubusercontent.com/wiki/CalixtoTheBugHunter/talos/Engineering-Standards.md
```

Substitute the page name from the wiki URL, and fetch fresh — a quote that was verbatim when the PR
was opened is a paraphrase if the page changed since. Per
[§ Issues are never independent of the SPEC](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#issues-are-never-independent-of-the-spec):

> An issue that restates the spec in its own words is a second source of truth, and second sources of
> truth drift. Cite and quote instead.

The same standard applies to the diff itself: a wiki rule paraphrased into a code comment, a README,
or a repo doc is a second source of truth and is reported as one.

---

## Rule 6 — The mechanical conventions, by link

These are on the wiki and are not restated here. Read
[§ Git conventions](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#git-conventions)
and [§ CI pipeline order](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order),
and confirm each against the PR rather than against the author's account of it:

- The [Conventional Commit](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#conventional-commits)
  title, with a **scope from the board's Area field** — check the item's Area, not what the scope
  plausibly could be.
- The [branch prefix](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#branching),
  and everything in
  [§ Protection rules on `main`](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#protection-rules-on-main):
  1 approval, linear history via squash-merge, conversation resolution, signed commits.
- **Every required check green**, in the pipeline order that page lists.

```bash
gh pr view <N> --repo CalixtoTheBugHunter/talos --json statusCheckRollup,commits,reviewDecision,mergeable
```

A red or missing required check is a finding on its own, and so is a **skipped** one: per
[§ CI pipeline order](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order),
"Every stage is a required status check on `main`", so a stage that did not run has not passed.

These checks are cheap and they are also the least interesting part of the review. Do not let them
substitute for Rules 1–4: a PR can satisfy every mechanical convention and still implement something
the wiki does not say, which is the case this whole skill exists for.

---

## Rule 7 — A finding is reported, never fixed here

The reviewer reports. Fixing what a review finds is a separate act by the author, and
[RIPER-5](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#riper-5-how-an-agent-executes-an-issue)
states it for the `Review` mode directly:

> | **Review** | Verify the result against the plan, the acceptance criteria, and every constraint page touched | Fixing what it finds — a fix is a new Plan and a new Execute |

**Do not push a commit to the PR under review, and do not edit the branch to make a finding go away.**
Two reasons, and the second is the one that bites:

- A reviewer who fixes the diff is reviewing their own work on the next pass, and the adversarial
  posture is gone — there is no longer a party trying to refute it.
- A silently fixed finding is a finding nobody counted. The author never learns the criterion was
  unmet, and the pattern repeats on the next PR.

Report each finding with the evidence a reader can open — file and line in the diff, the criterion it
fails, the SPEC line it violates, and what would have to change. A finding stated as an opinion is
not reviewable; a finding anchored to a SPEC line is.

The same applies to the board. Per
[§ A failed review returns the item to `In progress`](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#a-failed-review-returns-the-item-to-in-progress),
findings move the item **back to `In progress`** — the one backwards edge in the machine:

> **A review that produces findings moves the item back to `In progress` — the one backwards edge in
> this machine, and the only one.**

A gap found in review is different and still goes to `Blocked`; see Rule 8. Do not invent any other
backwards transition — per
[Decision 44](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions),
"A named exception is enforceable; an unnamed one becomes a habit of moving items backwards whenever
it is convenient."

---

## Rule 8 — A SPEC gap found in review goes to a human, never to the reviewer's judgement

A review is exactly where a gap surfaces: the diff does something the wiki does not cover, and the
reviewer is the first person to compare the two. That is not a reviewer's call to make. From
[Contributing § If you contribute with an AI agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills):

> A skill that hits something the SPEC does not answer raises a **SPEC gap** for a human decision and
> the [Decision Log](Decision-Log). It does not guess, and neither should you.

[`spec-driven-change`](../spec-driven-change/SKILL.md) owns the escalation procedure — what to state,
who decides, how it is recorded. What is specific to review:

- **Neither approve nor reject on the gap.** Report every finding that does not depend on it, and mark
  the gap-dependent part undecided. An approval that assumed an answer has legislated it.
- **The item moves to `Blocked`**, which per
  [the dev cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle)
  is "a real destination, not a failure to try harder", and whose gate to leave is that "The gap is
  decided in the [Decision Log](Decision-Log)".
- **Check [§ Open questions](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#open-questions) first.** A
  gap already listed there is known, and a PR depending on one is blocked rather than reviewable.

A reviewer's guess is worse than an author's, because it arrives with the authority of the gate. Per
[Contributing](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints),
"the wiki wins and the code is a bug" — and where the wiki is silent, nothing wins yet.

---

## Who reviews, and what this skill is not

**An agent's review is a self-check, not the approval `main` requires.** This is settled, not open —
[§ Who reviews](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#who-reviews):

> **An agent's review is a self-check, not the [1 approval](#protection-rules-on-main) the protection
> rules require.** An agent contributing to Talos runs under the maintainer's own credentials, so its
> approval is the author's approval under another name — and the claim an approving review makes, that
> *someone tried to break the change and could not*, is not one the party that wrote the change can make
> about itself.

So this skill produces a verdict and a findings list, and **says in the review that it is not the
required approval**. The findings are still worth producing first, because they are cheapest to fix
before a human reads the diff. What is forbidden is reporting the gate as passed.

The maintainer may [merge without a second reviewer](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#protection-rules-on-main)
— per [Decision 46](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions)
the owner is not bound by the protection rules. That is their call to make knowingly; it is not a
reason for this skill to soften a finding, because a bypassed merge "skips the **reviewer**, and
nothing else" — the loop, step 4, and the board item all still apply.

**It is also not the closing gate.** [Decision 40](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions)
draws the line and both halves are required:

> This does not replace [adversarial review](Engineering-Standards#review-is-adversarial-by-default) —
> a reviewer refutes a PR against the diff, an author confirms an item against its ticket, and an item
> can pass review with a criterion nobody checked.

So a passed review does not close the item: [`create-issue`](../create-issue/SKILL.md) closes it
criterion by criterion against the list it wrote. Rule 1 here reads the diff; that gate reads the
ticket. Neither makes the other redundant.

---

## The review output

Structure, not prose to copy. Everything in angle brackets comes from the diff, and every claim points
at something a reader can open.

```markdown
## Verdict

**<Not approved — N findings | Approved — no refutation succeeded | Approved with N deferred criteria | Blocked — SPEC gap>**

This is a self-check and not the 1 approval the protection rules require.

Refutations attempted: <what you tried to break, and how>

## Acceptance criteria, against the diff

| # | Criterion | Where in the diff | Verdict |
| --- | --- | --- | --- |

## Tests

<per test touching specified behavior: the SPEC line it asserts, and the regression it would catch>

## Constraint pages touched

<each page from Contributing's ordered list that the diff touches, the skill run, and the result>

## Step 4 of the loop

<does the diff now contradict any wiki page — and if so, was the wiki fixed in this PR>

## PR body

<issue reference · each wiki page linked with its line quoted verbatim, diffed against raw Markdown · DoD criterion or justification>

## Mechanical

<Conventional Commit title and scope vs. the item's Area · branch prefix · required checks · signing · linear history>

## Findings

1. **<file:line>** — <what is wrong> · <the SPEC line it violates, linked> · <what would have to change>

## Deferred criteria, if any

| # | Criterion | Follow-up item | Why deferrable |
| --- | --- | --- | --- |
| | <as authored> | <link — filed before this review, not promised> | <not a hard constraint, release gate, or Safeguards behavior> |

## Board

<Status this review implies: back to `In progress` on findings · `Blocked` on a SPEC gap · unchanged if it passes>
```

A `Verdict` of approved with an empty `Refutations attempted` is not an approval this skill produced.
Neither is one with a deferred criterion whose follow-up item column is blank.

---

## Questions the SPEC now answers

These three were gaps when this skill was written. They were decided rather than assumed, and they are
listed here because they are the ones a reviewer is most likely to try to settle by judgement.

| Question | Where it is decided |
| --- | --- |
| Does an agent's review satisfy the "**1 approval**" [protection rule](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#protection-rules-on-main)? | **No.** [Decision 43](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions) · [§ Who reviews](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#who-reviews) — see [*Who reviews*](#who-reviews-and-what-this-skill-is-not) |
| Which `Status` does a failed review move the item to? | **Back to `In progress`**, the one backwards edge. [Decision 44](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions) · [§ A failed review returns the item to `In progress`](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#a-failed-review-returns-the-item-to-in-progress) |
| May a partly satisfying PR be approved against follow-up work? | **Yes, with every unmet criterion named and each carrying a linked follow-up item** — and never for a hard constraint, a release gate, or Safeguards behavior. [Decision 45](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions) · [§ Approving a partial change](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#approving-a-partial-change) — see Rule 1 |

One more thing a reviewer will meet and should not mistake for a finding: per
[Decision 46](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions) the
**repository owner may merge or push directly**, so an unreviewed commit on `main` is not by itself a
violation. What still applies to it is everything the same decision keeps: the loop including step 4,
the [Conventional Commit](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#conventional-commits)
title, and the board item. A bypassed change that contradicts the wiki is the ordinary defect.

A **new** gap discovered while reviewing goes to a human and the Decision Log — it does not get a row
here and a guess in the review. The three above are decided; check
[§ Open questions](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#open-questions) for
the ones that are not.

---

## Sibling skills

[`spec-driven-change`](../spec-driven-change/SKILL.md) runs first and owns the loop, the escalation
procedure, and the authority order. [`create-issue`](../create-issue/SKILL.md) owns the item's
criteria — both when they are authored and when they are closed against evidence. The full
skill-to-constraint mapping is on the wiki so it cannot drift here:
[Contributing § If you contribute with an AI agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills).

Per Rule 3, this skill runs the constraint skill whose trigger the **diff** matches:
[`orchestration-boundary`](../orchestration-boundary/SKILL.md) on networking, adapters, MCP, or
credentials; [`safeguards-review`](../safeguards-review/SKILL.md) on tiers, the gate, allowlists, or
approval UI; [`agent-adapter`](../agent-adapter/SKILL.md) on adapter work;
[`gates-check`](../gates-check/SKILL.md) on UI, memory, launch, or token overhead.

A worked example of this skill rejecting a PR whose description claims a criterion its diff does not
meet is in [`references/verification.md`](references/verification.md).

---

## Checklist before posting a review

- [ ] The issue's criteria were read **from the issue**, and every one has a row pointing at the diff.
- [ ] No criterion was marked met on the strength of the PR body.
- [ ] Each test touching specified behavior was checked for the regression it would catch, by name.
- [ ] Every constraint page the diff touches was re-read in
      [Contributing's order](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints),
      and each matching constraint skill was run.
- [ ] Step 4 was checked against the pages the **diff** touches, not only the ones the issue cites.
- [ ] The body's quoted SPEC lines were diffed against the pages' raw Markdown, fetched fresh.
- [ ] Required checks, title scope, branch prefix, signing, and linear history were confirmed on the
      PR, not taken from the description.
- [ ] Every finding is reported with openable evidence, and nothing was fixed on the branch.
- [ ] Any SPEC gap went to a human and the Decision Log, and nothing gap-dependent was approved.
- [ ] The verdict states what was attempted, and an approval names a refutation that failed.
- [ ] The review says it is **not** the required approval.
- [ ] Any deferred criterion is named, carries a **filed** follow-up item, and is none of a hard
      constraint, a release gate, or a Safeguards behavior.
- [ ] The `Status` the review implies is stated — `In progress` on findings, `Blocked` on a gap.
