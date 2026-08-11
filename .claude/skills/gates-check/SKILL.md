---
name: gates-check
description: Guards the two release gates that block v1.0 — the eight performance budgets and the accessibility gate. Use this BEFORE writing code whenever a change adds or restyles a view, adds a control, a chart, a metric, or a state; allocates or retains anything at launch or per session; adds a dependency, an asset, or a bundled resource; touches launch, window creation, or the app's startup path; adds a timer, a poll, an observer, or a live indicator; or changes what Talos assembles into a prompt — Project Library context, guidelines, history, or any new injected context. Also use it when a request would "just add a small spinner", "poll for changes", "refresh every few seconds", "add a chart to the Monitor", "hard-code the color/size for now", "include the whole file in the prompt", or defer accessibility, contrast, VoiceOver, keyboard, or a budget measurement to a follow-up issue. Requires every new UI surface to be checked for VoiceOver labels, keyboard reachability, Reduce Motion, Reduce Transparency, text size at 200%, and AA contrast in both appearance modes; requires new injected context to be justified against the 5% token-overhead budget; forbids introducing a polling timer; requires every chart and metric to have a non-visual equivalent; and treats a gate failure as blocking the release rather than deferrable.
---

# Gates check

Talos ships with two gates that are not review opinions. From
[MVP Definition of Done § Notes on the harder criteria](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#notes-on-the-harder-criteria):

> **#9 and #10 are gates, not aspirations.** They block the release. The budgets exist precisely so
> that "lightweight" and "accessible" are not opinions at review time.

And the reason the numbers exist at all, from
[Vision & Principles § Budgets that make the above testable](https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable):

> A principle you cannot measure is a wish.

**SPEC:** [Vision & Principles § Budgets](https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable)
· [Essential Tools § Accessibility](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#accessibility)
· [MVP Definition of Done](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#checklist)
· [MVP DoD § Notes on the harder criteria](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#notes-on-the-harder-criteria)
· [Foundations: Accessibility](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility)
· [§ How the gate is checked](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#how-the-gate-is-checked)
· [Foundations: Interaction & Keyboard § No mouse-only paths](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#no-mouse-only-paths)
· [Foundations: States & Feedback § Nothing polls](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#nothing-polls)
· [§ First feedback under 100 ms](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#first-feedback-under-100-ms)
· [Design System: Foundations § The platform is the design system](https://github.com/CalixtoTheBugHunter/talos/wiki/Design-System#the-platform-is-the-design-system)
· [§ Liquid Glass is inherited, never applied](https://github.com/CalixtoTheBugHunter/talos/wiki/Design-System#liquid-glass-is-inherited-never-applied)
· [Foundations: Tone § Structure over prose](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Tone#structure-over-prose)
· [Talos Guidelines § Editable Talos Guidelines](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#editable-talos-guidelines)
· [Engineering Standards § CI pipeline order](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order)
· [Verification](https://github.com/CalixtoTheBugHunter/talos/wiki/Verification)

This skill **cites** the SPEC; it does not restate it. Rules live on the wiki pages linked here and
nowhere else — read the page, do not trust a summary in this file. Anything that looks like a rule
in this file without a link next to it is a bug in this file. The one place this file reproduces the
SPEC is the budget table in Rule 1, and it is reproduced as a **verbatim quote** with its citation,
because a budget you have to leave the page to read is a budget nobody checks.

This is a **constraint skill**, not a workflow one. Per the
[skills table](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills),
constraint skills "guard a specific hard constraint and are run by whichever workflow skill is
active" — so it is invoked from `execute-issue`, `review-pr`, or
[`spec-driven-change`](../spec-driven-change/SKILL.md), and it does not own a
[dev-cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle)
transition. It never replaces the workflow skill that called it.

Under [RIPER-5](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#riper-5-how-an-agent-executes-an-issue),
this skill belongs in **Research** and **Plan**. That placement is load-bearing here more than
anywhere else: most gate failures are *architectural* — a polling design, a hand-placed glass
container, a view built on hard-coded values, a context assembler that injects a whole file — and
they are cheap to avoid in Plan and expensive to unwind in Execute, where "Any deviation, however
small" is forbidden. A violation this skill finds during **Review** is not fixed in place: "a fix is
a new Plan and a new Execute".

Both gates are **hard constraints**, listed third and fifth in
[Contributing § Before you write code](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints),
where hard means "rejected rather than negotiated. A PR that violates one will be closed regardless
of code quality."

---

## Why this skill exists

Because these two gates fail differently from every other constraint in Talos: **no single change
breaks them.** A boundary violation is greppable
([DoD #11](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#checklist)) and
a misclassified action is one reviewable line. A budget is lost 3 MB and 40 ms at a time, by twenty
changes that were each individually defensible, and the release gate fails months later with no
diff to point at.

The accessibility gate fails the same way, with an extra twist: the change that omits a VoiceOver
label still works perfectly for the person who wrote it and for the person who reviewed it. Nothing
is red, nothing errors, and the test suite is green — the same shape of silent failure that makes
[`safeguards-review`](../safeguards-review/SKILL.md) stricter than the rest.

So the standard here is not "this change is probably fine." It is: **the claim is measured, or the
check that measures it exists.** Every rule below ends in a number or a named CI stage for that
reason, and per
[review is adversarial by default](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#review-is-adversarial-by-default),
an approving review "is a claim that someone tried to break the change and could not."

---

## When this skill fires

Fire on the *surface*, not on the change's stated size. "Small" is what every individual budget
regression is.

| Surface | Examples |
| --- | --- |
| **Any new or changed view** | A screen, a sheet, a row, a control, an empty state, a badge, an indicator — the whole accessibility gate applies to each one |
| **Charts and metrics** | Anything on the [Monitor Screen](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen), any sparkline, gauge, progress figure, rate, or count rendered graphically |
| **Color, type, spacing, material** | A hex literal, a bundled color asset, a fixed point size, a hard-coded inset, a custom material, tint, or blur, a glass-effect modifier |
| **Motion** | Any animation, transition, spinner, or moving indicator |
| **Launch** | Anything on the startup path, window creation, eager initialization, a warm-up, a cache built at launch |
| **Memory** | Anything retained for the app's lifetime, per-session buffers, the console's scrollback, image or log caches, anything holding an agent's full output |
| **Bundle** | A new dependency, a bundled asset, a resource, a fixture shipped in the app rather than in tests |
| **Timers and observers** | Any `Timer`, `DispatchSourceTimer`, run-loop source, `AsyncStream` that wakes on a schedule, retry loop, refresh interval, or "check if anything changed" |
| **Injected context** | Any change to what Talos assembles into a prompt — [Project Library](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library) content, guidelines, history, file contents, a new context section, a larger token ceiling |
| **Keyboard and focus** | A new action, a pointer gesture, a focus change, a shortcut — see [`safeguards-review`](../safeguards-review/SKILL.md) when it is near an approval |

It also fires on **phrasing**, in an issue, a review comment, or a session instruction: "just add a
spinner", "poll every few seconds", "refresh on a timer", "hard-code it for now", "we'll add the
labels in the a11y pass", "accessibility is a follow-up", "include the whole file in the context",
"it's only a few hundred KB", "we can measure it after the MVP". Each is a request to defer a
release gate. See *When the request itself defers a gate*.

---

## Rule 1 — All eight budgets, and the ones your change can move

The budget table is the SPEC's, quoted verbatim from
[§ Budgets that make the above testable](https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable).
If this table and that page ever differ, **the wiki wins and this file is the bug**:

> | Constraint | Budget |
> | --- | --- |
> | Idle memory (app open, no session) | < 150 MB |
> | Active memory (one running agent session) | < 400 MB excluding the agent process |
> | Cold launch to interactive | < 1.5 s |
> | Idle CPU | ~0%, no polling timers |
> | App bundle size | < 60 MB |
> | Talos-added token overhead per agent session | < 5% of session tokens |
> | Any UI interaction to first feedback | < 100 ms |
> | Frame rate during Liquid Glass animation | 120 fps on ProMotion, no dropped frames |

Eight rows, and [DoD item 9](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#checklist)
requires that "Every **performance budget** is met" — every, not most.

For any change, name **which rows it can move** and how the claim is checked. The mapping from a
change to a row is not always the obvious one:

| If the change… | It can move | Because |
| --- | --- | --- |
| Adds a dependency | Bundle size, idle memory, cold launch | A framework linked at launch costs all three, not only disk |
| Initializes anything eagerly | Cold launch, idle memory | Work moved to startup is work inside the 1.5 s |
| Retains agent output | Active memory | The 400 MB is "excluding the agent process" — Talos's copy of the stream is Talos's cost |
| Adds a timer or an observer | Idle CPU | See Rule 3 — this one is a prohibition, not a measurement |
| Adds an animation or a glass container | 120 fps on ProMotion | See Rule 4 |
| Adds a control or an interaction | First feedback < 100 ms | See Rule 5 |
| Changes what goes into a prompt | Token overhead < 5% | See Rule 6 |
| Adds a bundled asset or fixture | Bundle size | Including test fixtures shipped in the app target rather than the test one |

A change that can move a row and offers no measurement has not met this rule. "It should be
negligible" is the sentence that spends a budget.

---

## Rule 2 — Every new UI surface is checked against the whole accessibility gate

[Essential Tools § Accessibility](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#accessibility)
opens with the binding line:

> Accessibility is a **release gate, not a backlog item.**

It owns the list of six requirements — read it there; this file does not copy it. That page is the
authority, and
[Foundations: Accessibility](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility)
says so: "it owns the list of six requirements. This page never restates that list", adding "Where
the two pages appear to disagree, the gate wins."

For **every** view the change adds or touches:

- [ ] **VoiceOver: label, hint, and role.** "**Every control has a label**", plus a hint "wherever
      its effect is not obvious from the label", and "**Every element's role is real. Nothing is
      marked decorative to avoid having to describe it.**"
      ([§ VoiceOver](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#voiceover)).
- [ ] **Keyboard-reachable, with no pointer-only path.** The gate is "Complete **keyboard
      navigation** with no mouse-only paths", and "one pointer-only affordance fails
      [MVP DoD item 10](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#checklist)"
      ([§ No mouse-only paths](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#no-mouse-only-paths)).
      A gesture is allowed only as a shortcut for an action that is already keyboard-reachable — "A
      gesture that is an action's sole path is out of reach of VoiceOver too — two gates failed
      instead of one."
- [ ] **Focus order follows reading order, focus is visible, focus never moves on its own** — the
      single sanctioned exception is a new approval prompt
      ([§ Focus](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#focus)).
- [ ] **Reduce Motion.** No state change is communicated only by an animation: "a spinner that is the
      only sign work is running says nothing once the motion is gone"
      ([§ Reduce Transparency and Reduce Motion](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#reduce-transparency-and-reduce-motion)).
- [ ] **Reduce Transparency.** The binding line covers all three at once:

      > **No information in Talos is carried by the material, by motion, or by color alone.**

      If a surface's meaning depends on translucency, on layering, or on where a glass boundary
      falls, "that meaning is unavailable to a Reduce Transparency user and the surface is wrong."
- [ ] **AA contrast in both appearance modes**, met by inheritance rather than by hand: Dark and
      Light mode and contrast "arrive with Apple's semantic colors", and "A hex literal in a Talos
      view is therefore a defect, not a shortcut"
      ([§ Most of the gate is inherited](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#most-of-the-gate-is-inherited)).
      Same for a bundled color asset and a custom tint
      ([the platform is the design system](https://github.com/CalixtoTheBugHunter/talos/wiki/Design-System#the-platform-is-the-design-system)).
- [ ] **Text size holds at 200%.** "**Every surface holds its layout at 200%**: no clipping, no
      truncation that removes meaning, no overlap. A layout that works only at 100% is a defect, as a
      Light-mode-only view is." And "**No fixed point sizes anywhere**"
      ([§ Text size](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#text-size)).
      Localization compounds it: layouts must also tolerate **+40% string growth**
      ([§ Localization](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice#localization)).
- [ ] **Never by color alone.** "**Approval and denial, success and failure, and tier are never
      distinguished by color alone**" — each carries a text label or an SF Symbol
      ([§ Never by color alone](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#never-by-color-alone)).
- [ ] **All five states exist**, and each is reachable by VoiceOver — a surface shipping without
      Empty, Loading, Ready, Failed, and Denied "is **incomplete**"
      ([the five states every surface owes](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#the-five-states-every-surface-owes)).
      Empty answers specifically to the gate: "VoiceOver reads it and its action"
      ([what each state answers to](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#what-each-state-answers-to)).
- [ ] **Any new shortcut appears in the menu bar** beside its command — "a keystroke with no menu
      entry is one the accessibility gate cannot see"
      ([§ Menus carry the shortcuts](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#menus-carry-the-shortcuts)).

Two shortcuts that are not available here. **Glass is inherited, never applied** — no glass-effect
modifier, no glass container of Talos's own, no custom material behind a Talos surface
([§ Liquid Glass is inherited, never applied](https://github.com/CalixtoTheBugHunter/talos/wiki/Design-System#liquid-glass-is-inherited-never-applied))
— which is also what makes the Reduce Transparency degradation the system's work rather than a path
somebody has to write. And **there is no Talos value to reach for**: no palette, type scale, spacing
grid, motion curve, or icon set exists to pick from
([Decision 19](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#design-decisions), a
[Root Talos Guideline](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#root-talos-guidelines)
at rank 1 of the
[authority order](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#authority-order),
AI-editable `❌ Never`).

---

## Rule 3 — No polling timer, ever

The budget row is a prohibition, not a threshold: "Idle CPU | ~0%, **no polling timers**". There is
no acceptable interval, so this rule needs no measurement — the presence of the timer is the
finding.
[Foundations: States & Feedback § Nothing polls](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#nothing-polls)
states the positive form:

> A live indicator updates from an **event** — a streamed token, a tool call, a session record —
> never from a timer that wakes to check. A spinner that costs CPU while idle fails a release gate.

- [ ] Nothing in the change wakes on a schedule to ask whether something happened. No `Timer`, no
      `DispatchSourceTimer`, no `Task` sleeping in a loop, no run-loop source, no "refresh every N
      seconds", no retry loop that spins while idle.
- [ ] Every live indicator is driven by an **event** whose source is named in the plan.
- [ ] No progress bar advances on a timer — "no animated bar that advances on a timer rather than on
      an event"
      ([honest progress](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#honest-progress)).
      That section also forbids a progress figure Talos did not measure: "**Talos never renders a
      progress figure it did not measure.**"
- [ ] No approval prompt gains a timeout. That is a separate and stricter rule owned by
      [`safeguards-review`](../safeguards-review/SKILL.md) — "an approval on a clock is consent
      nobody gave"
      ([the gate fails closed](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed)) —
      and a timer there is a SPEC change, not an implementation detail.

The one thing that is **not** a polling timer: an animation the system drives while something is
actually happening, and a timer that exists only for the duration of real work and is torn down with
it. The test is whether anything wakes while Talos is idle. If the answer is "only every few
seconds", the answer is yes.

Where a change genuinely needs to know that something outside Talos changed, that is an
event-source design question, and an event source the SPEC does not name is a gap — raise it rather
than reaching for an interval.

---

## Rule 4 — Motion keeps 120 fps, and carries no meaning of its own

The budget is "120 fps on ProMotion, no dropped frames" during Liquid Glass animation, and
[Ready](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#what-each-state-answers-to)
answers to it directly. The SPEC also names the cheapest way to lose it, in
[§ Liquid Glass is inherited, never applied](https://github.com/CalixtoTheBugHunter/talos/wiki/Design-System#liquid-glass-is-inherited-never-applied):
"hand-placed glass containers layered on each other are the cheapest way to lose it."

- [ ] Animation uses **system animation defaults** — Talos "never defines" a motion curve, duration
      table, or easing set
      ([the platform is the design system](https://github.com/CalixtoTheBugHunter/talos/wiki/Design-System#the-platform-is-the-design-system)).
- [ ] No hand-placed glass, and no glass layered on glass.
- [ ] The animation carries **no information** — Rule 2's Reduce Motion row, restated as a
      performance concern because it is checked in the same place.
- [ ] Nothing animates on a timer rather than an event (Rule 3).

---

## Rule 5 — First feedback under 100 ms, separately from completion

From [§ First feedback under 100 ms](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#first-feedback-under-100-ms):

> So **acknowledgement is separate from completion**: every interaction acknowledges immediately and
> then shows progress, and nothing waits for the work to finish before admitting it started. An
> interaction silent until it succeeds looks like one that never arrived, so the user presses again.

- [ ] Every new interaction acknowledges within 100 ms, on a path that does not depend on the work
      completing.
- [ ] A long operation **shows its state rather than freezing** — "an interface that stops answering
      has already told the user it crashed"
      ([§ First feedback under 100 ms](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#first-feedback-under-100-ms)).
- [ ] Nothing on the interaction path does synchronous I/O, SQLite work, or file reads on the main
      thread.

---

## Rule 6 — New injected context is justified against the 5% budget

The budget row is "Talos-added token overhead per agent session | < 5% of session tokens", and
[§ Budgets](https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable)
defines exactly what counts:

> **Talos-added token overhead** is the context Talos injects (Project Library assembly, guidelines,
> history) versus the tokens the agent would have used from the raw user prompt. It is measured on
> the [Monitor Screen](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen)
> and it is a release gate, not a nice-to-have.

Same page: "This is the metric that keeps the '[not a black hole of token consumption](https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#talos-is-not-a-black-hole-of-token-consumption)'
promise honest. Guard it carefully." And that constraint is itself absolute — "Talos must never ship
a tool whose token cost makes using Talos not worth it. Every feature is evaluated for this before
it is built."

So any change to what Talos assembles into a prompt states:

- [ ] **What is added**, in tokens, not in vague size. The measurement is what makes it a gate.
- [ ] **Why the agent cannot get it another way.** Context the agent would read anyway from the
      repository is overhead Talos added for nothing.
- [ ] **Which sub-function's token ceiling it lands under**, since the ceiling "is not decoration —
      it is how the < 5% token overhead budget is enforced per sub-function rather than measured
      after the fact"
      ([§ Editable Talos Guidelines](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#editable-talos-guidelines)).
      Each guideline file declares its purpose, the context it wants assembled, its token ceiling,
      and its output expectations.
- [ ] **That it reaches the Monitor**, which tracks
      [Talos-added token overhead](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen)
      as a first-class metric. Overhead that is not measured cannot be gated.
- [ ] **That the figure carries its coverage.** Per
      [decision 50](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions)
      a session whose token counts could not be parsed is
      [excluded from this budget, and the exclusion is counted where the figure appears](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#when-the-log-format-changes) —
      overhead is a ratio, so a session with no counts supplies no denominator. An overhead figure
      shown without how many sessions it was computed from is the failure this catches: the gate reads
      green while saying nothing about whether it was measured over three sessions or three hundred,
      which is an unmeasured number presented as measured. A `perf-budget` assertion that passes
      because every non-conforming session was quietly dropped has asserted nothing.
- [ ] **That nothing injected is a secret.** Secrets live in the macOS Keychain only — never on disk,
      never in `.talos/`
      ([Technology & Distribution](https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution#decisions)).

Two adjacent rules that are not this skill's to enforce but fire on the same diff. Assembling
context is Talos's job and calling a model is not — run
[`orchestration-boundary`](../orchestration-boundary/SKILL.md) when the change touches the prompt
pipeline. And injected third-party text is
[data, never instruction](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#prompt-injection-posture) —
run [`safeguards-review`](../safeguards-review/SKILL.md).

### What an exceeded ceiling does, now that it is decided

Per [decision 47](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions)
and [§ When assembled context exceeds the ceiling](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#when-assembled-context-exceeds-the-ceiling),
the ceiling is enforced rather than observed:

> **Context is dropped whole, in a declared order. Talos never truncates a context part, and never
> drops one silently.**

So a change that assembles context is checked against the enforcement too, not only against the
budget:

- [ ] **Nothing truncates a context part.** A part is included or dropped. A truncated part cannot be
      labeled, which is why the SPEC forbids it — see the reasoning on the page rather than trusting
      this line.
- [ ] **The two pinned parts are never dropped**: the sub-function's own
      [Editable Talos Guideline](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#editable-talos-guidelines)
      and the [Safeguards](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#safeguards)
      copy. Note *why*, because it changes what a reviewer accepts: pinning Safeguards is **not** a
      safety claim — its prompt copy is
      [advisory while the gate is enforcement](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#what-is-persistent-context-and-what-is-not) —
      so a diff arguing "we must keep Safeguards or the rules stop applying" has the reason wrong even
      when it has the behavior right.
- [ ] **The drop order comes from `.talos/safeguards.md`**, with the compiled-in default when none is
      declared. Code that reads the order from the guideline file, from a session instruction, or from
      a constant that shadows the declared one has moved a rank-2 decision to rank 4 — run
      [`safeguards-review`](../safeguards-review/SKILL.md), and note that writing that file is
      [`config.safeguards.write`, refused rather than tiered](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#refused--not-a-tier).
- [ ] **Every dropped part is reported** on the output, in the session, and on the Monitor. A silent
      drop is the failure this decision exists to prevent, and the output label is the one the SPEC
      already owned — [missing context is labeled where the output is read](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#missing-context-is-labeled-where-the-output-is-read).
- [ ] **A pinned-parts overflow does not start the session**, and it is
      [**Failed**, not **Denied**](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#the-five-states-every-surface-owes).
      Recording it as a denial names a decision nobody made. No action is attempted, so no tier
      applies and `taxonomy: 1` is unchanged.
- [ ] **Dropping is deterministic** — same inputs and same declared order, same parts dropped, so the
      overhead #58 must reproduce stays reproducible.

---

## Rule 7 — Every chart and metric has a non-visual equivalent

A chart is a UI element, so it is inside the gate on the same terms as a button — this rule is the
existing gate rows applied to the one surface where they are easiest to forget, not a new rule.
Three SPEC lines converge on it:

- "**Every element's role is real.** Nothing is marked decorative to avoid having to describe it."
  ([§ VoiceOver](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#voiceover)) —
  a chart labelled decorative to avoid describing it is the named failure.
- "**No information in Talos is carried by the material, by motion, or by color alone.**"
  ([§ Reduce Transparency and Reduce Motion](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#reduce-transparency-and-reduce-motion)) —
  a series distinguished only by line color carries information by color alone.
- The gate itself requires "Full **VoiceOver** labeling", and *full* is given weight on the
  [Foundations](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#voiceover)
  page rather than left to interpretation.

This matters most on the [Monitor Screen](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen),
which [DoD item 7](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#checklist)
requires to show "**tokens, estimated cost, duration, and success rate** for every session run" —
four numbers that are also the input
[Self-improver](https://github.com/CalixtoTheBugHunter/talos/wiki/Sub-function-Self-improver) will
later tune against. A metric only a sighted user can read fails item 10 while item 7 passes.

- [ ] The **underlying values are reachable without the graphic** — read by VoiceOver, and available
      as text or a table on the surface itself.
- [ ] **Series and states are distinguished by more than color** — a label, a symbol, or a shape as
      well.
- [ ] The chart is **keyboard-reachable and navigable**, with no pointer-only tooltip holding the
      only copy of a value. A tooltip is pointer-only, so it fails
      [no mouse-only paths](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#no-mouse-only-paths)
      and the VoiceOver gate together.
- [ ] It **holds its layout at 200% text size**, in both appearance modes.

These four are also what
[Foundations: Tone § Structure over prose](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Tone#structure-over-prose)
depends on when it asks for a table, a chart, or a diagram over a paragraph: "**Structure that only
works visually is a defect, not a shortcut.**" Where it cannot meet these, "a plain list is the
correct answer and a picture is not." So Tone never licenses a graphic this rule would reject — a
change citing Tone to justify a chart still owes every box above.
- [ ] Cost is **labeled an estimate wherever it appears** and never presented as a bill — cost is "an
      **estimate**, always labeled as such in the UI"
      ([how cost is measured](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured)),
      and the wording is decided in
      [§ Cost copy](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Content-and-Voice#cost-copy).
      The non-visual equivalent carries that label too, or it is a bill to a VoiceOver user.
- [ ] It renders **no figure Talos did not measure**
      ([honest progress](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#honest-progress)).

---

## Rule 8 — A gate failure blocks the release and is never a follow-up

This is the rule the other seven rest on.
[MVP DoD § Notes](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#notes-on-the-harder-criteria)
is unambiguous — "**#9 and #10 are gates, not aspirations.** They block the release" — and
[items 9 and 10](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#checklist)
read "**Every** performance budget is met" and "**Every** accessibility gate is met". Talos "**v1.0
ships** when all of the following are true", so an unmet gate is not a known issue shipping
alongside the release; it is the release not shipping.

Consequences to apply in review:

- **"We'll do the a11y pass later" is not available.** "Accessibility is not a phase at the end" —
  `a11y` is a first-class commit scope and board area precisely so the work is "planned, reviewed,
  and released like any other work"
  ([§ How the gate is checked](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#how-the-gate-is-checked)).
  A follow-up issue is not a mitigation; it is the deferral the gate exists to prevent.
- **A green build is not evidence.** `perf-budget` and `a11y` "are release gates, so they are checks
  rather than a review checklist"
  ([CI pipeline order](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order)) —
  but a check only asserts what somebody wrote into it. A new surface with no `a11y` coverage passes
  the stage and fails the gate.
- **A gate is not traded against a feature.** These are hard constraints — "rejected rather than
  negotiated"
  ([Contributing](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints)) —
  so the outcome is a smaller feature, a different design, or a SPEC change decided by a human. It is
  never a shipped exception.
- **A budget with no measurement is an unmet budget**, per "A principle you cannot measure is a
  wish."

If a change genuinely cannot meet a gate as specified, that is a **Blocked** item and a SPEC
question, not a judgement call for the implementer —
[Blocked is "a real destination, not a failure to try harder"](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle).

---

## Rule 9 — Name the CI check that will verify each claim

Every claim this skill asks for maps to a named stage in
[§ CI pipeline order](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order) —
`lint` → `build` → `test` → `spec-guard` → `perf-budget` → `a11y` — where "Every stage is a required
status check on `main`."

The accessibility half of this mapping is owned by
[Foundations: Accessibility § How the gate is checked](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#how-the-gate-is-checked),
which carries the authoritative requirement-to-verification table. Read it there. The performance
half:

| Claim | Verified by |
| --- | --- |
| Idle and active memory | `perf-budget` |
| Cold launch < 1.5 s | `perf-budget` |
| Idle CPU ~0%, no polling timers | `perf-budget`, plus review for the timer itself — Rule 3 is a prohibition a measurement can miss on a fast runner |
| Bundle size < 60 MB | `perf-budget` |
| Token overhead < 5% | `perf-budget`, and measured in the product on the [Monitor Screen](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen) |
| First feedback < 100 ms | `perf-budget` ([Loading](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#what-each-state-answers-to)) |
| 120 fps during Liquid Glass animation | **Not `perf-budget`** — a hosted runner is not ProMotion. A [manual pre-release check](https://github.com/CalixtoTheBugHunter/talos/wiki/Verification) on an internal ProMotion display, per [decision 49](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions), plus **review** for the mechanism (Rule 4) ([Ready](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#what-each-state-answers-to)) |
| No hex literal, no fixed point size | `lint`, per [decision 56](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions) — SwiftLint `custom_rules` plus `tools/design-guard/`. **Two residues are review-enforced**, listed in `tools/design-guard/README.md` § What is NOT covered, and `lint` claims nothing about them |
| Every a11y row | `a11y` (XCUITest), per the gate's own table |
| Non-visual equivalent, never color alone | `a11y` for label/role/keyboard; **review** for whether meaning survives — the gate's table assigns "Never by color alone" and the material/motion judgement to review |

- [ ] The change names its stage, and where the stage does not yet assert the claim, it says so
      rather than implying coverage.
- [ ] A new surface **adds `a11y` coverage**, rather than relying on a stage that does not know the
      surface exists.

**Four gates are not verified by a stage at all.** Per
[decision 49](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions) and
[Verification](https://github.com/CalixtoTheBugHunter/talos/wiki/Verification), the **120 fps** row,
**VoiceOver comprehensibility**, **Reduce Transparency usability**, and
[**DoD #5**](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#notes-on-the-harder-criteria)'s
denial path are documented **manual pre-release checks** with their measured values recorded. Claiming
`perf-budget` or `a11y` covers one of them is the false-coverage this rule exists to prevent — and note
what does *not* follow: a manual gate is still a gate, so Rule 8 applies to it unchanged.

**The `lint` rows are decided, and two residues are still review-enforced.**
[Decision 56](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions)
settles the former open question: seven of the eight no-values classes are enforced by SwiftLint —
five by new `custom_rules`, two by rules already enabled — and the eighth, a bundled color asset, is
**split**, because the asset is a directory of JSON no SwiftLint configuration can reach while the
lookup that resolves it is ordinary Swift. `tools/design-guard/` owns the asset and is a step inside
`lint` rather than a stage of its own. So a hex literal, a fixed point size, `#colorLiteral`,
`Font.custom`, a hand-placed blur, a glass-effect modifier, a frame or spacing value written as a
numeric literal, and a bundled color asset — the asset and the `Color("Name")` lookup both — **are**
caught by `lint` and may be claimed as such. What may **not** be claimed is listed in
`tools/design-guard/README.md` § What is NOT covered: class 6's named-constant loophole and a custom
`Material` type stay **review-enforced**. Whether a hand-placed *system* material is forbidden at all
is not a residue but an undecided question, in
[Decision Log § Open questions](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#open-questions).

---

## Worked example — a PR that adds a token chart to the Monitor

The verification case for this skill. A PR titled *"feat(monitor): add token usage over time"* adds
a line chart of tokens per session to the Monitor Screen. It refreshes every 5 seconds so the chart
stays live during a running session, draws three series in red, amber, and green, uses
`.font(.system(size: 11))` for the axis labels and a `Color(hex: "3B82F6")` accent to match the
series, sits inside a hand-placed glass card, and shows a value in a hover tooltip. Cost per session
appears under the chart as `$0.42`. The PR notes "a11y labels to follow in the a11y pass" and adds
no `a11y` coverage. It builds, `perf-budget` is green on the CI runner, and it looks good in a
screenshot.

**Rejected**, and not on one finding. How the skill gets there:

1. **Fires on the surface** — a new view, a chart, colors, a font size, a material, a timer, and a
   metric. Seven of the nine rules apply before anyone discusses whether the chart is a good idea.
2. **Rule 3 — the 5-second refresh is the clearest defect.** "Idle CPU | ~0%, **no polling timers**"
   is a prohibition with no acceptable interval, and the positive form is already specified: a live
   indicator updates "from an **event** — a streamed token, a tool call, a session record — never
   from a timer that wakes to check"
   ([nothing polls](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#nothing-polls)).
   The session records the chart wants are exactly such an event. Green `perf-budget` does not rescue
   it — a 5-second wake is easy to miss on a busy runner, which is why Rule 3 is review-enforced too.
3. **Rule 2 — the values are the defect, not the styling.** `Color(hex:)` and a bundled accent are
   "a contrast promise — two appearance modes, two contrast settings, every text size — that nobody
   is maintaining"; the fixed 11 pt breaks "**No fixed point sizes anywhere**" and the 200% layout
   requirement. There is no Talos palette or type scale to pick from
   ([Decision 19](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#design-decisions)).
   The hand-placed glass card breaks
   [inherited, never applied](https://github.com/CalixtoTheBugHunter/talos/wiki/Design-System#liquid-glass-is-inherited-never-applied)
   and puts the 120 fps budget at risk (Rule 4) while removing the free Reduce Transparency
   degradation.
4. **Rule 7 — three series by color, and a tooltip holding a value.** Red/amber/green alone carries
   information by color alone; the tooltip is pointer-only, so the same element fails
   [no mouse-only paths](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#no-mouse-only-paths)
   and the VoiceOver gate at once. The chart needs the values reachable as text, series marked by
   label or symbol, and keyboard navigation.
5. **Rule 7 again — `$0.42` is presented as a bill.** Cost is "an **estimate**, always labeled as
   such in the UI", including in the non-visual equivalent.
6. **Rule 2 — the five states are missing.** A chart with no Empty state is incomplete, and Empty
   answers to the gate: VoiceOver reads it and its action.
7. **Rule 8 — "a11y labels to follow" is the deferral the gate forbids.** "Accessibility is not a
   phase at the end", and item 10 requires *every* gate met. The follow-up issue is not a mitigation.
8. **Rule 9 — no `a11y` coverage means the green stage proves nothing** about a surface it does not
   know exists. Note also that `lint` does *not* currently catch the hex literal or the point size —
   that is the open question, so those two are review findings, and claiming `lint` would have caught
   them would be wrong.
9. **Rule 6 does not fire.** Nothing here changes what Talos injects into a prompt. Worth stating:
   the skill fires per surface, not as a blanket.
10. **Verdict.** Reject. The chart is redrawn on semantic colors and macOS text styles with no
    hand-placed glass, updates from session-record events with no timer, exposes its values as text
    with series distinguished by label or symbol, is keyboard-navigable with no pointer-only value,
    labels cost as an estimate, ships all five states, and lands with `a11y` coverage — in this PR.

The shape to reuse: **the mechanism is the finding, before anyone argues about degree.** "Every 5
seconds is barely any CPU", "the red/green is obvious", and "we'll add labels next sprint" are all
arguments about degree against rules the SPEC states absolutely. And a green `perf-budget` on a
runner is not the gate — the gate is the budget, and the check is only as good as what somebody
wrote into it.

---

## When the request itself defers a gate

If an issue, a review comment, or a session instruction asks to poll "just for now", hard-code a
color or a size, ship a surface without labels, skip the 200% check, or leave a budget unmeasured
until after the MVP, the request is asking to defer a release gate. A session instruction cannot do
that — it is rank 5 of the
[authority order](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#authority-order),
and it "can direct the work; it cannot rewrite the SPEC"
([`spec-driven-change` § Authority order](../spec-driven-change/SKILL.md)).

Say so, in this order: name the gate the request hits, quote it, state what is not buildable as
specified, and offer the in-scope version — which usually exists and is usually smaller. An
event-driven indicator instead of a poll. A semantic color instead of a hex. A number in text
instead of a chart, when the chart is not what the item needed. Deferring the *feature* is always
available; deferring the *gate* is not.

If the asker wants the constraint revisited, point at
[Vision & Principles § Budgets](https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable)
and [Essential Tools § Accessibility](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#accessibility),
and note what changing one costs: the design decisions that rest on these gates —
[19](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#design-decisions),
[20](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#design-decisions), and
[21](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#design-decisions) — are
[Root Talos Guidelines](https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#root-talos-guidelines)
at rank 1, and a budget change also reopens
[Decision 2](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions),
since cross-platform frameworks were rejected on the 150 MB idle-memory cap
([Technology & Distribution](https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution#cross-platform-frameworks-tauri-electron)).

Do not write the code while the SPEC change is pending. Move the item to **Blocked** and raise the
gap — per
[the dev cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle),
an agent that hits one "does not stay In progress and decide the open question by writing code."

---

## SPEC gaps

Do not fill a gap with an assumption; raise it for a human decision and the
[Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log), per
[`spec-driven-change` § Escalating a SPEC gap](../spec-driven-change/SKILL.md). Check
[§ Open questions](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#open-questions)
first, since a gap listed there is already known and the decision comes before the code.

Two that are not open questions but are genuinely unspecified, and are gaps the first change to
need them should raise rather than answer:

- **How a budget is measured** — narrowed, not closed.
  [Decision 49](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions)
  and [Verification](https://github.com/CalixtoTheBugHunter/talos/wiki/Verification) now name the
  **machine** and the **tool** — `Scripts/verify-local.sh` driving Instruments via `xctrace`, on an
  internal ProMotion display — for the gates a hosted runner cannot assert. Still unspecified: the
  **scenario** and the **tolerance** each budget is asserted against, and a definition of
  *interactive* before the cold-launch row can fail honestly.
- **How budget headroom is allocated between changes** — nothing says what share of 60 MB or 150 MB
  a single change may take. This is the mechanism by which these gates fail, so a change consuming a
  visible share of a budget should say so out loud rather than assume it is affordable.

A change that needs one of these answers moves to **Blocked**, and everything in it that does not
depend on the answer continues.

---

## Checklist before marking a change ready

- [ ] [Vision & Principles § Budgets](https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable)
      and [Essential Tools § Accessibility](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#accessibility)
      were read in this session, from the wiki, before the first edit.
- [ ] Every budget row the change can move is **named and measured** — not assumed negligible.
- [ ] Every new or changed surface was checked against the whole gate: VoiceOver label, hint, and
      real role; keyboard-reachable with no pointer-only path; focus order and visible focus; Reduce
      Motion; Reduce Transparency; AA contrast in both modes; layout at 200% text size; never by
      color alone; all five states; any new shortcut in the menu bar.
- [ ] **No polling timer was introduced** — every live indicator updates from a named event, and no
      progress advances on a clock.
- [ ] Motion uses system defaults, glass is inherited rather than applied, and no meaning is carried
      by motion or material.
- [ ] Every new interaction acknowledges within 100 ms, independently of completion.
- [ ] Any new injected context states its token cost, why the agent cannot obtain it otherwise, the
      sub-function ceiling it lands under, and that it reaches the Monitor.
- [ ] Anything acting on an **exceeded** ceiling drops whole parts in the order
      `.talos/safeguards.md` declares, never truncates, never drops the guideline or the Safeguards
      copy, reports every dropped part, and treats a pinned-parts overflow as **Failed** rather than
      **Denied**.
- [ ] Every chart and metric has a **non-visual equivalent**: values reachable as text and by
      VoiceOver, series distinguished by more than color, keyboard-navigable, no pointer-only value,
      cost labeled an estimate.
- [ ] No value was hard-coded — no hex literal, no bundled color asset, no fixed point size, no
      custom material, tint, or spacing grid.
- [ ] Each claim **names the CI stage** that verifies it, a new surface **added `a11y` coverage**, and
      no claim was attributed to a stage that does not yet assert it.
- [ ] **Nothing was deferred to a follow-up issue.** A gate failure blocked the change, and where the
      gate could not be met as specified the item went to **Blocked** and to a human.
