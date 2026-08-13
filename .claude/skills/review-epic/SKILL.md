---
name: review-epic
description: Checking whether an epic on the Talos board is ready to move to Done. Use this whenever an epic's readiness is in question — "is this epic ready to close", "check epic #N", "can we mark this epic done", "review this epic before closing it". Never entered directly outside that question; create-issue invokes it as the delegate step of closing an item that happens to be an epic. Runs a fast path rather than re-deriving full per-criterion evidence, because every sub-issue already passed create-issue's own closing gate and review-pr's adversarial review individually — closing an epic asserts only the epic's own goal and done condition, never the leaves' criteria restated. Checks three things and nothing more: every linked sub-issue is Done on the board, not merely closed on GitHub; the epic's own done condition verified against the Spec Pages it cites, against live system state rather than by trusting a description; and a smoke test for regression — quick, because the leaves' own reviews already attempted to break the change and this only confirms nothing has drifted since. A gap in any of the three sends the item back — to In progress on a failed check, to Blocked on a SPEC gap in the done condition — and this skill reports findings rather than closing over them.
---

# Review epic

The fast path for closing an epic, distinct from closing a leaf. It exists because an epic's leaves
each already paid the full evidentiary cost of closing individually — re-running that cost a second
time at the epic level would buy nothing the leaves didn't already prove.

**SPEC:** [Engineering Standards § Closing an epic: the `review-epic` fast path](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#closing-an-epic-the-review-epic-fast-path)
· [§ Closing an item is the authoring gate run backwards](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#closing-an-item-is-the-authoring-gate-run-backwards)
· [§ Epics are authored too](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#epics-are-authored-too-against-a-different-list)
· [§ Review is adversarial by default](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#review-is-adversarial-by-default)
· [Decision Log § Process decisions](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions) — decisions 30, 40, 65

This skill **cites** the SPEC; it does not restate it. Rules live on the wiki pages linked here and
nowhere else — read the page, do not trust a summary in this file. Anything that looks like a rule in
this file without a link next to it is a bug in this file.

This is **not** a workflow skill in its own right. Per
[decision 65](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions),
[`create-issue`](../create-issue/SKILL.md) still owns the `In review` → `Done` transition; this skill
is the delegate it runs when the item being closed is an epic, "the same way a workflow skill runs a
constraint skill for the diff shape it matches." Run `create-issue` first if the item's own closing
gate — the leaf case — has not been checked; this skill assumes every leaf already cleared it.

---

## When this fires

| Situation | Fires? |
| --- | --- |
| Asking whether an epic is ready to move to `Done` | **Yes** |
| Closing an epic, once its sub-issues are confirmed `Done` | **Yes** — this is the check that confirms it |
| Closing a **leaf** issue | No — [`create-issue`](../create-issue/SKILL.md) directly; this skill's fast path is epic-specific because leaves have no sub-issues to roll up and no separate done condition to check |
| Authoring or rewriting an epic | No — [`create-issue`](../create-issue/SKILL.md) Rule 6 |
| Reviewing a PR that closes out an epic's last sub-issue | No — [`review-pr`](../review-pr/SKILL.md) reviews the PR; this skill runs afterward, against the epic, once that sub-issue is actually `Done` |
| A sub-issue itself is not yet `Done` | No — stop; report which sub-issue is open rather than running the fast path against an incomplete set |

Phrasings that fire it: "is this epic ready to close", "check epic #N", "can we mark this epic done",
"review this epic before closing it", "is #N ready to be moved to Done".

---

## Rule 1 — Every linked sub-issue is `Done` on the board, not merely closed on GitHub

The first of the three checks, and the cheapest to get wrong by conflating GitHub's own `state` with
the board's `Status` field. A closed issue and a `Done` board item are not the same claim — an issue
can be closed as a duplicate, closed without merging, or closed by a bot, none of which is `Done`.

```bash
gh issue view <epic> --repo CalixtoTheBugHunter/talos --json body,title
gh api graphql -f query='
  query { repository(owner:"CalixtoTheBugHunter", name:"talos") {
    issue(number: <epic>) { subIssues(first: 50) { nodes { number title state } } }
  } }'
gh project item-list 5 --owner CalixtoTheBugHunter --format json --limit 200
```

Cross-reference every sub-issue number from the `subIssues` query against the project item list's
`status` field — read the board, per
[the dev cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle),
because Status is what the machine actually tracks. **A sub-issue that is `CLOSED` on GitHub but not
`Done` on the board stops this skill here.** Report which one and why, and do not proceed to Rules 2
or 3 against an incomplete leaf set.

---

## Rule 2 — The epic's own done condition, against the Spec Pages it cites

Per [§ Epics are authored too](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#epics-are-authored-too-against-a-different-list),
an epic carries "**a goal, and the condition under which the epic is done** — not the union of its
leaves' criteria, because an epic that is only its leaves needed no epic." That condition — usually a
"this epic is done when" checklist in the body — is what this rule checks, and it is checked **against
the SPEC pages the epic cites**, not against the PR descriptions of its sub-issues.

For each item in the epic's done condition:

1. State the claim as the epic worded it.
2. Find the evidence **in the live system** — a config file, a script, a running check, a script's
   output — not a sub-issue's closing comment. A sub-issue closed cleanly does not by itself prove the
   epic-level claim; it proves the leaf's own narrower criteria.
3. Re-derive at least the claims that are mechanically checkable, rather than trusting that because
   the leaves are `Done` the aggregate must hold — an epic's done condition is frequently a claim about
   the **system as assembled**, which no single leaf's tests were scoped to catch.

A claim with no evidence, or evidence that is merely a sub-issue's own assertion, is not met — same
standard as
[closing an item](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#closing-an-item-is-the-authoring-gate-run-backwards):
"'Done' asserted in a closing comment is the failure mode."

---

## Rule 3 — A smoke test for regression, not a full re-review

The leaves' own reviews already attempted to break the change — per
[§ Review is adversarial by default](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#review-is-adversarial-by-default),
that is what an approving review on each of them already claims. This rule does not repeat that
attempt. It asks a narrower question: **has anything drifted since those reviews passed?**

A smoke test here is:

- A live, current signal — a required check's latest run status, a ruleset or config read back from
  the system it configures, a script run against the current tree — never a cached memory of a past
  result.
- **Quick by design.** The fast path only holds if this step stays cheap; a smoke test that grows into
  a full re-verification has stopped being this rule and become Rule 2 or a full review.
- Reported with what was checked and what it showed, not asserted as "still passing" with no evidence
  named — the same discipline
  [`review-pr`](../review-pr/SKILL.md) applies to a reviewer's refutation attempt.

A finding here is a **regression**, distinct from an unmet done-condition item under Rule 2: something
that was true when the leaves closed and is no longer true now.

---

## What a failure sends the item to

Per [the dev cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle)
and [decision 65](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions):

| Finding | Status this implies |
| --- | --- |
| A linked sub-issue is not `Done` on the board | Unchanged — the epic was never ready to check; report which sub-issue |
| A done-condition item has no live evidence, or the evidence contradicts it | `In progress` — the same backwards edge [decision 44](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions) names for an ordinary review finding |
| The done condition turns out to depend on something the SPEC does not answer | `Blocked` — a SPEC gap, raised per [`spec-driven-change`](../spec-driven-change/SKILL.md#escalating-a-spec-gap), never settled by this skill's own judgement |
| The smoke test finds a regression | `In progress` — the same as an unmet done-condition item |
| All three checks pass | `Done` — `create-issue` completes the transition with this skill's evidence as the closing comment |

---

## The output

```markdown
## Sub-issues

| # | Title | GitHub state | Board Status |
| --- | --- | --- | --- |

## Done condition, against the SPEC

| Claim (as the epic worded it) | Evidence in the live system | Met? |
| --- | --- | --- |

## Smoke test

<what was checked, live · what it showed · regression found, or none>

## Verdict

**<Ready for Done | Not ready — N findings | Blocked — SPEC gap>**
```

---

## Sibling skills

[`create-issue`](../create-issue/SKILL.md) owns the `In review` → `Done` transition and invokes this
skill for the epic case; it closes a leaf directly, without this skill, and it is where the closing
comment and the `Done` move actually happen once this skill's checks pass.
[`review-pr`](../review-pr/SKILL.md) is what already reviewed each sub-issue's PR — this skill does
not repeat that adversarial pass, per Rule 3. A SPEC gap surfaced by Rule 2 or Rule 3 goes to
[`spec-driven-change`](../spec-driven-change/SKILL.md#escalating-a-spec-gap) like any other gap, never
decided here.

---

## Checklist before reporting an epic ready for `Done`

- [ ] Every sub-issue's board `Status` was read from the board, not inferred from GitHub's `state`.
- [ ] Any sub-issue not `Done` stopped the check here, named, with nothing further run against it.
- [ ] Every item in the epic's stated done condition has evidence read from the live system, not from
      a sub-issue's closing comment.
- [ ] The smoke test checked something current — a live run, a live config read-back — not a cached
      or remembered result.
- [ ] A finding is reported, not silently fixed; the `Status` it implies is stated.
- [ ] A SPEC gap went to a human and the Decision Log, never settled by this skill alone.
