## What and why

<!-- What changes, and the reasoning behind the shape it takes. -->

Closes #

## SPEC traceability

Per [Engineering Standards § Spec-driven workflow](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#spec-driven-workflow),
this PR references the wiki page it implements and the DoD criterion it advances.

**Spec Page:** <!-- link to the wiki page(s) this PR implements -->

**DoD criterion advanced:**
<!--
State the numbered MVP DoD criterion (https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done)
this PR advances. If none, you must state why — "not applicable" alone is not
a reason:

Not applicable, because ___
-->

## Constraint checklist

Per [Contributing § Before you write code](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints),
these are rejected rather than negotiated. Check each only if this PR was verified against it.

- [ ] **Orchestration boundary** — no model API client, no MCP client, no API key. ([Architecture: The Orchestration Boundary](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary))
- [ ] **Performance budgets** — idle memory, launch time, token overhead are unaffected or measured. ([Vision & Principles § Budgets](https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable))
- [ ] **Safeguards** — no tier widened, no irreversible action made allowlistable. ([Safeguards & Autonomy](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy))
- [ ] **Accessibility** — VoiceOver, keyboard, Reduce Motion/Transparency, contrast, text size checked for any new surface. ([Essential Tools § Accessibility](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#accessibility))
- [ ] None of the above apply to this change.

## Did the SPEC need updating?

- [ ] No — the SPEC already covered this and nothing here contradicts it.
- [ ] Yes — and the wiki edit is **in this PR** (link the diff/page below).
- [ ] Yes, but the wiki edit is **not** in this PR. <!-- This PR is not mergeable per Engineering Standards § Spec-driven workflow step 4 — the SPEC is fixed in the same PR, never silently diverged from. -->

## Tests

<!-- What asserts the SPEC's stated behavior, and what regression each assertion would catch. -->
