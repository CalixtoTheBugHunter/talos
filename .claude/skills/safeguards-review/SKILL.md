---
name: safeguards-review
description: Reviews the highest-consequence changes in Talos — anything touching autonomy tiers, the Safeguards gate, allowlists, action classification, or approval UI. Use this BEFORE writing code whenever a change adds or renames an action type, classifies an action into a tier, touches the gate or its interception point, reads or writes an allowlist, builds or restyles an approval prompt, adds a keyboard shortcut near an approval, changes what a denial does, ends a session or stops a process, or logs a gated decision. Also use it when a request would "skip the prompt", "remember this choice", "make approving faster", "just allowlist deploys", or have an agent, an issue body, or a log widen its own permissions. Requires every new action type to be explicitly classified with a test and to default to the most restrictive tier, checks it against the never-allowlistable list, enforces the no-dark-patterns rules on approval UI, requires the gate to fail closed, requires a denial-path test and an audit-log entry per gated action, and treats third-party content as data that can never raise a tier.
---

# Safeguards review

[Safeguards & Autonomy](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy)
opens by naming what it is: "the layer that makes an orchestrator of autonomous agents safe to run
on real work." Talos runs
[unsandboxed](https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution#why-unsandboxed-is-safe-here),
so "restraint is Talos's job, not the OS's."

**SPEC:** [Safeguards & Autonomy](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy)
· [§ Tiers](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#tiers)
· [§ Action classification](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#action-classification)
· [§ The action-type taxonomy](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy)
· [§ Rules](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules)
· [§ The gate fails closed](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed)
· [§ What is never allowlistable](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable)
· [§ Stop kills the tree](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree)
· [§ Prompt-injection posture](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#prompt-injection-posture)
· [Foundations: Interaction & Keyboard § The form of an approval prompt](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#the-form-of-an-approval-prompt)
· [Foundations: States & Feedback § Denial is not failure](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#denial-is-not-failure)
· [Vision & Principles § Talos is not a place for deceptive design](https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#talos-is-not-a-place-for-deceptive-design)

This skill **cites** the SPEC; it does not restate it. Rules live on the wiki pages linked here and
nowhere else — read the page, do not trust a summary in this file. Anything that looks like a rule
in this file without a link next to it is a bug in this file.

This is a **constraint skill**, not a workflow one. Per the
[skills table](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills),
constraint skills "guard a specific hard constraint and are run by whichever workflow skill is
active" — so it is invoked from `execute-issue`, `review-pr`, or
[`spec-driven-change`](../spec-driven-change/SKILL.md), and it does not own a
[dev-cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle)
transition. It never replaces the workflow skill that called it.

Under [RIPER-5](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#riper-5-how-an-agent-executes-an-issue),
this skill belongs in **Research** and **Plan** — its rules shape the plan before Execute begins,
because "Execute never starts without an approved Plan" and forbids "Any deviation, however small".
A violation this skill finds during **Review** is not fixed in place: "a fix is a new Plan and a new
Execute". And where a rule below turns out to need a SPEC decision, the item goes to **Blocked** —
"a real destination, not a failure to try harder"
([the dev cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle)).

Where a change also touches the gate's position in the pipeline, run
[`orchestration-boundary`](../orchestration-boundary/SKILL.md) too: that skill's
[common misreading](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-common-misreading)
section owns the case where a tool call streams straight through and the gate is gone. And where the
change is in an adapter, run [`agent-adapter`](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills): it owns
[stop kills the tree](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree)
and [a tool call and a permission request are two events](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#a-tool-call-and-a-permission-request-are-two-events),
which are Safeguards rules enforced on the adapter side — an
[agent CLI's own prompt is never a Talos approval](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions).

---

## Why this skill is stricter than the others

Because the failure mode is **silence**. A broken build fails loudly, a wrong color is visible, and
a boundary violation is greppable
([DoD #11](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done)). An action
misclassified as read tier does none of that. It does not error, it does not log a denial, and it
does not prompt — the SPEC spells this out in
[§ Action classification](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#action-classification):

> An action misclassified as read tier does not error, does not log a denial, and does not prompt —
> it simply runs, and the first evidence is the thing it did.

So a green test suite is not evidence here. The tests that would have caught it are the ones nobody
wrote, which is why several rules below are *"and a test exists"* rather than *"and the code is
correct."* This is also why
[review is adversarial by default](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#review-is-adversarial-by-default)
matters more on this surface than anywhere else — the standard it sets is that "A test that passes
against both the specified and the unspecified behavior verifies nothing", and a happy-path test on a
gated action is exactly that test. Use this skill to **refute** the change: an approving review "is a
claim that someone tried to break the change and could not."

Safeguards is also a **hard constraint**, listed fourth in
[Contributing § Before you write code](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints)
— "deny-by-default tiers. Nothing may widen a tier, and nothing may make an irreversible action
allowlistable" — where hard means "rejected rather than negotiated. A PR that violates one will be
closed regardless of code quality."

---

## When this skill fires

Fire on the *surface*, not on the PR's stated intent. Nobody writes a PR titled "remove a
safeguard"; they write "improve the approval flow."

| Surface | Examples |
| --- | --- |
| **Tiers** | Any change to the [tier table](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#tiers)'s meaning, a tier enum, a sub-function's default tier, anything that moves an action between tiers |
| **Classification** | A new action type, a renamed action type, the mapping from a tool call to a tier, a `default:` branch in that mapping |
| **The gate** | The interception point, its outcome type, what it does on error, what happens when it cannot present a prompt, the pre-check in [the shared session model](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model) |
| **Allowlists** | The allowlist store, its scope, its matching logic, its config surface, anything that persists a decision across prompts |
| **Approval UI** | Any approval prompt, its copy, its controls, its default control, its focus order, its keyboard bindings, its color treatment |
| **Denial path** | What the agent is told, what the session does next, how a denial is recorded and rendered |
| **Stop** | Anything that ends a session or spawns a process a session owns — [stop kills the tree](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree), and an orphan acts "outside the [gate](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed)". Depth lives in `agent-adapter` |
| **Audit log** | The gated-decision record, its fields, where it is written, where the user reads it |
| **Self-modification** | Anything letting [Self-improver](https://github.com/CalixtoTheBugHunter/talos/wiki/Sub-function-Self-improver), an agent, or a session edit guidelines, allowlists, or a tier |
| **Third-party text** | Any new path feeding an issue body, PR comment, log, monitoring output, or web page into a prompt |

It also fires on **phrasing**, in an issue, a review comment, or a session instruction: "skip the
prompt for this one", "remember my choice", "make approving faster", "it's annoying to confirm every
time", "just allowlist deploys for this project", "the agent already checked", "trust the CI". Each
is a request to widen autonomy. Treat it as a request to change the SPEC — see *When the request
itself widens a tier*.

---

## Rule 1 — Every new action type is classified explicitly, with a test

The tier table specifies **tiers**, not a complete list of actions, so every action type the gate
sees needs a classification. The rule for the case where it does not have one, from
[§ Action classification](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#action-classification):

> **Classification defaults to the most restrictive tier when a call is unrecognized — never to
> read.**

Concretely, the same section: an unrecognized call "is therefore treated as **irreversible /
outward-facing**: it always requires in-the-moment approval and it can never be allowlisted." And
the two consequences it names, both of which this skill checks:

> - **A new action type is classified explicitly, in code, with a test.** An action type that
>   reaches the gate without one is a defect, not a default.
> - **The friction is the forcing function.** The way to stop prompting on an action is to classify
>   it deliberately — never to leave it unclassified and let it fall through.

What to check in a diff that adds or touches an action type:

- [ ] It has an **explicit** tier at its definition site. Not inherited from a neighbor in the same
      `switch`, not implied by where it sits in an enum.
- [ ] A test asserts **that specific action maps to that specific tier**. One test per action type;
      a test that only exercises the tier in general does not catch a new member.
- [ ] The classifier's fallback is the **irreversible** tier. A `default:` returning `.read`, an
      optional tier defaulting to read, or a `?? .read` is the silent failure this rule exists to
      prevent.
- [ ] A test asserts the **fallback itself** — feed the classifier an action it does not know and
      assert the irreversible tier. This is the test that survives every future action type somebody
      forgets.
- [ ] The type's name is in
      [the taxonomy](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy)
      and spelled exactly as that table spells it. The taxonomy is versioned and a name in it is a
      name users have written into `.talos/`.
- [ ] Allowlist matching is **exact string equality** — the rule is absolute:
      "**Matching is exact string equality. The dots are not a hierarchy, and no allowlist entry is
      ever a prefix, a wildcard, or a pattern.**"
      ([§ Naming and matching](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#naming-and-matching)).
      An allowlist on `git.push` must not match `git.push.protected`; a prefix match here is how an
      irreversible action becomes allowlistable without the list being edited.
- [ ] If the action is a **rename**, the old name is **retained as an alias** and not dropped, and no
      shipped name is reused for a different meaning — read
      [§ Adding, renaming, and removing a type](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#adding-renaming-and-removing-a-type)
      for all four cases, including why *removing* a name is the dangerous one.
- [ ] A **🔒** type was not moved, and no type was lowered to read tier. Either needs a new
      [Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log) row.
- [ ] Writes to Safeguards, an allowlist, or a tier are **refused, not tiered** — they are
      [not a tier](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#refused--not-a-tier)
      at all, and no approval opens them. A diff that gates one of these behind a prompt has made an
      absolute limit approvable.

**The taxonomy is decided, and extending it is still a Decision Log append.** Decision
[37](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions) settled
the set as `taxonomy: 1`, so a change no longer picks a name freely: adding a type is "a Decision Log
append, a row above, and a classifier test"
([§ Adding, renaming, and removing a type](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#adding-renaming-and-removing-a-type)).
Deciding the set did **not** retire the unrecognized-call rule —
[§ Action classification](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#action-classification)
states the relationship: "the taxonomy is what Talos knows today, and the rule is what happens the
first time an agent calls something it does not."

---

## Rule 2 — Check every new action against the never-allowlistable list

[§ What is never allowlistable](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable)
is a list, and its preamble is the binding part:

> No configuration, no user preference, and no agent request can move these out of
> in-the-moment approval:

Read the list on the wiki — it is eight items and this file will not copy them. For each new or
changed action, check it against **every** row, including the last one, which is a catch-all rather
than an example: "**Any action against a system not declared in `connectors.yaml`**".

How this rule actually gets broken — none of these look like editing the list:

| Shape | Why it is the same violation |
| --- | --- |
| A **new** action that *is* one of the listed things under a different name | `syncBranch` that force-pushes, `cleanup` that deletes, `publish` that ships a package. The list names outcomes, not function names |
| A **composite** action whose steps include a listed one | An action is classified by the most restrictive thing it can do. A "prepare release" that tags, publishes, and deploys is irreversible, whatever the middle steps are |
| An allowlist entry with **wildcard or prefix matching** | Forbidden outright: "no allowlist entry is ever a prefix, a wildcard, or a pattern" ([§ Naming and matching](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#naming-and-matching)). A pattern that can match an irreversible action makes it allowlistable indirectly, and matching is where the list gets bypassed without being edited |
| An allowlist granted at the **wrong scope** | Allowlists are **per project, per action type** — never global, never "trust everything" ([§ Rules](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules)) |
| A **session-level** override, or a "for the rest of this session" checkbox | The tier is "**Not allowlistable. Ever.**" ([tiers](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#tiers)). "Ever" includes the next ten minutes. A session instruction cannot widen it — rank 5 does not override rank 2 in the [authority order](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#authority-order) |
| An **undeclared target** | Per the list's last row. A new connector, host, or service reached before it is in `connectors.yaml` is top-tier regardless of what the action does |

The tier is not softened by the action being reversible *in practice*. "anything that spends money"
and "anything that sends data to a third party" are in the tier's own definition
([tiers](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#tiers)) — a
refundable charge and a deletable post are still both.

---

## Rule 3 — No dark patterns on the approval prompt

This is where the review is most likely to be argued with, because every item here makes approving
slightly slower. That is the intent. The SPEC's own justification, from
[§ Rules](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules):

> The "no pre-checked destructive defaults" rule is not politeness — it is the
> [no deceptive design](https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#talos-is-not-a-place-for-deceptive-design)
> constraint applied to the one screen where a misclick costs the most.

And the rule it justifies, from the same section:

> Every prompt states plainly **what will happen, where, and whether it can be undone.** No dark
> patterns, no pre-checked destructive defaults, no approve-by-Enter on irreversible actions.

The positive specification is
[Foundations: Interaction & Keyboard § The form of an approval prompt](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#the-form-of-an-approval-prompt) —
read it, because the prohibition alone is not a specification and the SPEC says so: "A prohibition on
one key is not a keyboard specification."

Checklist for any approval UI change:

- [ ] **The sentence comes first.** What will happen, where, and whether it can be undone, "before
      any control in it is reachable — the sentence first, the controls after, in reading order and
      focus order alike" ([the prompt's form](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#the-form-of-an-approval-prompt)).
- [ ] **Nothing is armed on arrival.** "**No pre-checked destructive default.** Nothing in a prompt
      is armed on arrival" (same section).
- [ ] **`↩` does not approve an irreversible action, on any surface.** The rule is absolute:
      "**`↩` never approves an irreversible or outward-facing action on any surface.**"
      ([§ Return never approves an irreversible action](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#return-never-approves-an-irreversible-action)).
      That section also states there is no shortcut to add later, and the
      [shortcut map](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#the-shortcut-map)
      is authoritative on which key does what at which tier — "A surface that binds one of these
      keys elsewhere is a bug."
- [ ] **The irreversible approve control is not the default control**, since default means the one
      `↩` activates ([the prompt's form](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#the-form-of-an-approval-prompt)).
- [ ] **Deny is at least as easy as approve.** Deny is `⎋` — "denial is a normal outcome, so the
      cheapest key is the safe one" ([shortcut map](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#the-shortcut-map))
      — while the costly outcome "gets no shortcut at all." A deny behind a menu, a second
      confirmation, a smaller or lower-contrast control, or more keystrokes than approve fails this.
- [ ] **Deny and approve are not adjacent and identical.** "Two controls that look the same, side by
      side, make the outcome a question of aim" (same section).
- [ ] **The consequence is not behind a hover or a disclosure.** "**Reversibility is stated in the
      prompt itself**, never in a tooltip or behind a disclosure", because "A prompt that hides its
      consequence behind a hover has put the most important word in the sentence somewhere the
      keyboard never goes" ([Approval copy](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice#approval-copy)).
      A tooltip is also pointer-only, so it fails
      [no mouse-only paths](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#no-mouse-only-paths)
      and the VoiceOver gate at the same time.
- [ ] **The copy names the operation and the target, and the approve label names the action.** Read
      [Approval copy](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice#approval-copy)
      for all four requirements — including "**No phrasing implies a recommendation.** The prompt
      reports; the user decides", which is where a prompt nudges without ever pre-checking anything.
- [ ] **Not color alone.** "**Approval and denial, success and failure, and tier are never
      distinguished by color alone**" — each carries a text label or an SF Symbol
      ([Accessibility § Never by color alone](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#never-by-color-alone)).
- [ ] **No approval from a notification.** "**An approval is never granted from a notification.**"
      A notification takes the user to the gate rather than acting for them
      ([States & Feedback § Notifications](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#notifications)).
- [ ] **Words follow the lexicon** — **Approve** / **Deny**, never `allow`/`block` or
      `accept`/`reject` ([the lexicon](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice#the-lexicon)).

"It's more convenient" is never the counter-argument, for the reason
[§ Return never approves an irreversible action](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#return-never-approves-an-irreversible-action)
gives: `↩` "clears prompts nobody read and confirms defaults nobody chose, faster than reading is
possible." Convenience on this screen is the failure mode, not a benefit traded against safety.

---

## Rule 4 — The gate fails closed

From [§ The gate fails closed](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed):

> **A gate that cannot obtain a decision denies. It never proceeds, and it never assumes consent.**

That section carries the table of cases — read it there. The distinction it draws is the one to check
in a diff: **cannot present** and **cannot reach the user** are denials; **has not been answered
yet** waits.

- [ ] Every error path out of the gate resolves to **denied**, not to "proceed" and not to a thrown
      error some caller swallows into a success.
- [ ] A prompt that cannot be presented — UI failure, window gone, app quitting — denies **and the
      agent is told**.
- [ ] **A pending prompt has no timer.** The same section: "an approval on a clock is consent nobody
      gave, and a *denial* on a clock is an outcome the user did not choose, recorded against them in
      a log that [names the actor](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules)."
      A new timeout on an approval prompt is a SPEC change, not an implementation detail.
- [ ] While waiting, the session **stays alive**, Talos
      [notifies that a session needs the user](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#notifications),
      and [stop stays reachable at `⌘.`](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#the-stop-guarantee-is-an-interaction-rule).
- [ ] A fail-closed denial is **logged with Talos as the actor**, not the user — per the same
      section, "a log that shows a user denial they never made is a wrong record rather than a
      cautious one."
- [ ] A test drives the failure path. The gate's error branch is the one no manual test session ever
      reaches.

---

## Rule 5 — Every gated action ships its denial path, tested

From [§ Rules](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules):

> - **A denial is a normal outcome.** The agent is told it was denied and continues; it never retries
>   the same denied action silently.

This is a [DoD](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done) criterion,
not a nicety — item 5 requires the gate "firing on each and **a denial handled cleanly**", and the
[notes](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#notes-on-the-harder-criteria)
say why it is the real test:

> **#5 — "a denial handled cleanly"** is the real test, not the happy path. Anyone can build an
> automator that works when you say yes. The requirement is that saying *no* leaves the agent
> informed, the session alive, and nothing half-applied.

So for **every** newly gated action, a denial test ships in the same change:

- [ ] The agent **is told** it was denied.
- [ ] The session **stays alive** — "the gate closes and the console keeps streaming"
      ([denial is not failure](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#denial-is-not-failure)).
- [ ] **Nothing is half-applied.** A multi-step action denied at step three leaves no partial state.
- [ ] **No silent retry** of the same denied action.
- [ ] It is **recorded as denied, not as an error**, "everywhere outcomes appear"
      ([same section](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#denial-is-not-failure)).
- [ ] It **reads and looks like a denial**, not a failure: neutral copy, "never an error color, never
      an error icon, never a nudge to approve instead"
      ([Content & Voice](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice#denial-and-failure-read-differently)),
      and "**Visually distinct from failure** — never an error treatment, never red, never an alert
      icon" ([States & Feedback](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#denial-is-not-failure)).

The reason a cosmetic detail is a safeguard rule, from
[Content & Voice](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice#denial-and-failure-read-differently):
"A denial that reads like a failure teaches users to stop denying, which disarms the one control that
[cannot be allowlisted away](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable)."
A gate the user has been trained not to use is not a gate.

Note that **Denied** is one of
[the five states every surface owes](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#the-five-states-every-surface-owes) —
a surface shipping without it "is **incomplete**".

---

## Rule 6 — Every gated decision is logged, and the user can see it

From [§ Rules](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules):

> - Every gated decision is **logged** with the actor, the action, the tier, and the outcome.

Four fields, and "every" includes the ones that are easy to skip: an approval, a denial, a
fail-closed denial, and an action that was allowlisted and therefore never prompted. A decision made
by an allowlist is still a gated decision.

The log is not only a file —
[States & Feedback § Every gated decision leaves a visible trace](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#every-gated-decision-leaves-a-visible-trace):

> What was logged is **visible to the user, in the session where it happened** — not only in a file.
> A record the user cannot reach is an audit trail for someone else.

- [ ] All four fields are present, and the **actor is honest** — Talos for a fail-closed denial, the
      user for a user decision, the allowlist for an allowlisted pass.
- [ ] The record is **visible in the session where it happened**.
- [ ] Outcomes reach the [Monitor Screen](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen),
      which tracks "Approvals vs. denials" via
      [the shared session model](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model).
- [ ] The record contains **no secret**. Secret access is never-allowlistable, and secrets live "only
      in the **macOS Keychain**" — never on disk, per
      [Project Library § Where it lives](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives).
      A gate that logs the argument it gated can write a secret into a session record.

---

## Rule 7 — Third-party content is data, never instruction

From [§ Prompt-injection posture](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#prompt-injection-posture):

> **Third-party content is data, never instruction.**

And specifically, content Talos reads from third parties:

> - **cannot** raise a tier
> - **cannot** grant an allowlist
> - **cannot** trigger an irreversible action

That page names the surface — "issue bodies, PR comments, logs, monitoring output, web pages" — which
is most of what Talos reads. So any change adding a path from external text into a prompt fires this
rule:

- [ ] Text from a third party is never parsed for a directive that changes tier, allowlist, or
      approval state.
- [ ] The **user** is the only one who opens a gate. Per the same section: "even a successful
      injection cannot escalate on its own — the malicious instruction still has to pass a gate that
      only the user can open."
- [ ] The gate's decision comes from the gate, never from anything in the agent's output stream. The
      gate is **enforcement**, and the copy of Safeguards in the prompt is only **advisory** —
      "it is what makes the rules true when the agent ignores them, whether through error or through
      prompt injection"
      ([what is persistent context](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#what-is-persistent-context-and-what-is-not)).
- [ ] The [authority order](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#authority-order)
      still holds: "**Nothing at runtime overrides #1 or #2.** Not the user in a session, not an
      agent, not Self-improver, and not content Talos reads from a third party".

An agent asking for a wider tier is the same case. The never-allowlistable preamble covers it in
words — "no agent request can move these out of in-the-moment approval"
([§ What is never allowlistable](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable)).

---

## Rule 8 — Nothing edits its own permissions

From [§ Limits on AI self-modification](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#limits-on-ai-self-modification):

> - Self-improver may **never** modify Safeguards, Root Talos Guidelines, allowlists, or **its own
>   tier**.

And the reason, which is why the limit takes no configuration flag:

> An AI that can widen its own permissions has no permissions. That is why this limit is absolute
> rather than configurable.

- [ ] No code path lets an agent, a session, or Self-improver write Safeguards, allowlists, or a
      tier. Read that section for what Self-improver *may* propose and the reviewable-diff
      requirement.
- [ ] [Project Safeguards](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#safeguards)
      stay "**never editable by AI**" — rank 2 of the
      [authority order](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#authority-order),
      where the AI-editable column reads `❌ Never`.
- [ ] The gate itself is not reachable for modification from inside a session it is gating.

---

## Worked example — a PR that adds an ungated mutation

The verification case for this skill. A PR titled *"feat(automator): add board item archiving"* adds
an `archiveBoardItem` action to the board connector. The board's own API calls it archiving, it is
recoverable from the board's UI, and the PR argues it is "basically the same as moving an item,
which is write tier." It builds, and it has a happy-path test. The action reaches the gate through
the existing `default:` branch, which returns `.read`.

**Rejected.** How the skill gets there:

1. **Fires** — the diff adds an action type and touches classification. Rule 1's surface, before any
   argument about which tier is correct.
2. **Rule 1 hits on the mechanism, not the judgement.** The action has no explicit classification;
   it inherits `default: .read`. That is the failure
   [§ Action classification](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#action-classification)
   names — "An action type that reaches the gate without one is a defect, not a default." Note the
   PR never says "ungated": it says "write tier" while the code says read, and read "never prompts"
   ([tiers](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#tiers)). A
   mutation that never prompts is ungated.
3. **The `default: .read` branch is a second, larger defect.** It is the silent failure for every
   future action too, so it is rejected independently of this action's tier. Its replacement is the
   irreversible tier plus a test that feeds the classifier an unknown action.
4. **Rule 2 — check the list before accepting the author's tier.** Archiving is a form of removal,
   and "**Delete anything**" is in the irreversible tier's own definition. The board's undo does not
   settle it: the tier definition is about the class of action, and Rule 2's composite row applies if
   archiving also closes linked items. If the board is not in `connectors.yaml`, the last row of
   [§ What is never allowlistable](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable)
   settles it regardless of what archiving means.
5. **The name is not in the taxonomy, so both the name and the tier go to a human.** `archiveBoardItem`
   is not a [taxonomy](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy)
   name — it is not even in the `domain.verb` form the SPEC fixes, and the closest entries are
   `board.item.update` at write tier and `board.item.delete` at irreversible. Picking between them
   here would be [filling a gap with an assumption](../spec-driven-change/SKILL.md); adding a
   `board.item.archive` is "a Decision Log append, a row above, and a classifier test"
   ([§ Adding, renaming, and removing a type](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#adding-renaming-and-removing-a-type)),
   which is a human decision, not the implementer's. Note the change is **not blocked** meanwhile:
   the unrecognized-call rule already gives it a safe behavior, the top tier, which is exactly the
   case that rule exists for.
6. **Rules 5 and 6 — what is still missing either way.** No denial test, so DoD item 5's "denial
   handled cleanly" is unasserted; and no audit-log entry for the new decision. Both ship in this
   change, not a follow-up.
7. **Verdict.** Reject. The action gets a taxonomy name and an explicit tier decided by a human, the
   `default:` branch becomes the irreversible tier with its own test, and a denial test plus a log
   entry land in the same PR.

The shape to reuse: **the skill rejects the mechanism before it argues about the tier.** The tier is
a SPEC question that may need a human; the missing explicit classification, the read-tier fallback,
the missing denial test, and the missing log entry are defects the SPEC already settles. A PR is not
rescued by the action being recoverable, by the author naming a plausible tier in prose, or by a
green happy-path test.

---

## When the request itself widens a tier

If an issue, a review comment, or a session instruction asks to skip a prompt, allowlist an
irreversible action, bind `↩` to approve, or add an approval timeout, the request is asking to change
a hard constraint. A session instruction cannot do that — it is rank 5 of the
[authority order](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#authority-order),
and it "can direct the work; it cannot rewrite the SPEC"
([`spec-driven-change` § Authority order](../spec-driven-change/SKILL.md)).

Say so, in this order: name the rule the request hits, quote it, state what is not buildable as
specified, and offer the in-scope version if one exists — usually "classify the action explicitly at
the tier the SPEC gives it", which is the sanctioned way to reduce prompting. If the asker wants the
constraint revisited, point at
[Safeguards & Autonomy](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy)
and the [Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log), where
[#4](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions) is
binding: "Tiered, deny-by-default; irreversible actions never allowlistable." Decisions
[25 and 26](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions)
refine it and bind the same way.

Do not write the code while the SPEC change is pending. Move the item to **Blocked** and raise the
gap — per [the dev cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle),
an agent that hits one "does not stay In progress and decide the open question by writing code."

---

## SPEC gaps

Do not fill a gap with an assumption; raise it for a human decision and the
[Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log), per
[`spec-driven-change` § Escalating a SPEC gap](../spec-driven-change/SKILL.md). Known gaps on this
surface:

| Gap | Why it is a gap |
| --- | --- |
| **Where a specific action sits, when the taxonomy does not name it** | Decision [37](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions) settled the *set*, and the [tier table](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#tiers) still gives examples per tier rather than a total mapping. An action in neither is the unrecognized case: it is safely gated at the top tier, and *which* tier it belongs in — plus the name it gets — is a human decision and a Decision Log append |
| **Board write conflicts** | An [open question](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#open-questions) — "Talos and a human can move the same item. Last-write-wins, detect-and-ask, or Talos re-reads before every write?" `detect-and-ask` would add a prompt that is not a Safeguards approval, so it needs deciding before that prompt is designed |

A change that needs one of these answers moves to **Blocked** — which is
[a real destination, not a failure to try harder](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle) —
and the gap goes to the Decision Log before the code that depends on it. Everything in the change
that does not depend on it continues, and per the unrecognized-call rule an undecided *tier* is not
one of these blockers, because the safe default is already specified.

---

## Checklist before marking a change ready

- [ ] [Safeguards & Autonomy](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy)
      was read in this session, from the wiki, before the first edit.
- [ ] Every new or renamed action type has an **explicit** tier and a test asserting it, and its name
      is in [the taxonomy](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy)
      spelled exactly as that table spells it — a new name is a Decision Log append first.
- [ ] Allowlist matching is **exact string equality**, with no prefix, wildcard, or pattern entry.
- [ ] No **🔒** type was moved, no type was lowered to read tier, and no write to Safeguards, an
      allowlist, or a tier was made approvable rather than
      [refused](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#refused--not-a-tier).
- [ ] The classifier's fallback is the **irreversible** tier, with its own test.
- [ ] Every new action was checked against **every row** of
      [what is never allowlistable](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable),
      including the undeclared-system row — and against composite actions, wildcard matching, and
      session-scoped overrides.
- [ ] Approval UI: sentence first, nothing armed on arrival, `↩` unbound on irreversible, approve not
      the default control, deny at least as easy as approve, not adjacent and identical, consequence
      not behind a hover, never color alone, no approval from a notification.
- [ ] Every error path out of the gate resolves to **denied**; no timer was added to a pending
      prompt; the fail-closed denial names Talos as the actor.
- [ ] A **denial-path test** ships for every newly gated action — agent informed, session alive,
      nothing half-applied, no silent retry, recorded and rendered as denied rather than failed.
- [ ] Every gated decision — including an allowlisted pass — logs actor, action, tier, and outcome,
      and is visible to the user in the session where it happened, with no secret in the record.
- [ ] No third-party text can raise a tier, grant an allowlist, or trigger an irreversible action.
- [ ] No agent, session, or Self-improver path can write Safeguards, allowlists, or a tier.
- [ ] Anything that would widen a tier was **declined and named as a SPEC change**, not built
      smaller.
- [ ] Every gap hit sent the item to **Blocked** and went to a human and the Decision Log — none was
      assumed, and none was settled by writing code.
