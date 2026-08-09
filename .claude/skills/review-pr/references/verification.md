# Verification fixture

A worked case for [`review-pr`](../SKILL.md), and the evidence for the acceptance criterion on
[issue #139](https://github.com/CalixtoTheBugHunter/talos/issues/139) that reads:

> - [ ] Verified against a sample PR whose description claims a criterion the diff does not meet,
>   which the skill must reject

Everything below is **synthetic**. No such issue, branch, or PR exists in the repository — the fixture
is a static input so the run is reproducible without publishing a defective PR. Re-run it by reading
the sample as though `gh pr view` and `gh pr diff` had returned it, applying the skill, and comparing
the result to *Expected findings*.

**Pass condition:** the verdict is **not approved**, and findings 1 and 2 are both produced. Finding 1
is the criterion the description claims and the diff does not meet — the case the criterion above
names. An approval, or a verdict that reports only the mechanical problems, is a **failure of the
skill**.

---

## Sample input

### The issue the PR closes — synthetic #900

> **Title:** Monitor Screen shows tokens, cost, duration, and success rate per session
>
> **Spec Page:** [Essential Tools § Monitor Screen](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen)
> **DoD:** [#7](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#checklist)
>
> **Acceptance criteria**
>
> 1. The Monitor lists every session run with its token counts.
> 2. Cost is shown and is **labeled as an estimate**, never presented as a bill.
> 3. Token parsing happens in the adapter; the Monitor receives counts and a model name.
> 4. The view updates from session events, with no polling timer.
> 5. Each metric has a non-visual equivalent for VoiceOver.

### The PR body — synthetic #901

> ## Adds the Monitor Screen
>
> Closes #900
>
> Implements [Essential Tools § Monitor Screen](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen).
> The Monitor tracks token cost, application performance, and success rate.
>
> All five acceptance criteria are met:
>
> - [x] 1 — every run is listed with its token counts
> - [x] 2 — cost is displayed and labeled as an estimate
> - [x] 3 — parsing is in the adapter layer
> - [x] 4 — the view refreshes as sessions progress
> - [x] 5 — VoiceOver labels added
>
> DoD: advances #7.

### The diff — synthetic

```diff
--- /dev/null
+++ b/Sources/TalosCore/Monitor/MonitorViewModel.swift
+struct SessionRow {
+    let id: UUID
+    let inputTokens: Int
+    let outputTokens: Int
+    let costUSD: Decimal
+    let duration: Duration
+    let succeeded: Bool
+}
+
+final class MonitorViewModel: ObservableObject {
+    @Published var rows: [SessionRow] = []
+
+    private var refresh: Timer?
+
+    func start() {
+        refresh = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
+            self?.reload()
+        }
+    }
+
+    // Reads the agent's own session log and pulls the usage line out of it.
+    private func reload() {
+        let log = try? String(contentsOf: sessionLogURL, encoding: .utf8)
+        for line in log?.split(separator: "\n") ?? [] where line.contains("tokens:") {
+            rows.append(parseUsageLine(line))
+        }
+    }
+}
```

```diff
--- /dev/null
+++ b/Sources/TalosCore/Monitor/MonitorView.swift
+struct MonitorView: View {
+    @StateObject private var model = MonitorViewModel()
+
+    var body: some View {
+        Table(model.rows) {
+            TableColumn("Tokens") { Text("\($0.inputTokens + $0.outputTokens)") }
+            TableColumn("Cost") { Text($0.costUSD, format: .currency(code: "USD")) }
+            TableColumn("Duration") { Text($0.duration.formatted()) }
+            TableColumn("Result") { Image(systemName: $0.succeeded ? "checkmark" : "xmark") }
+        }
+        .onAppear { model.start() }
+    }
+}
```

```diff
--- /dev/null
+++ b/Tests/TalosCoreTests/MonitorViewModelTests.swift
+@Test func loadsRows() async throws {
+    let model = MonitorViewModel()
+    model.start()
+    #expect(model.rows.isEmpty == false)
+}
```

Title: `feat(monitor): add the Monitor Screen`. Branch: `feat/monitor-screen`. Board Area on #900:
`Monitor`. All required checks green.

---

## Expected findings

### 1 — Criterion 3 is claimed and not met · Rule 1

The body checks criterion 3, "parsing is in the adapter layer". The diff parses the agent's session
log inside `MonitorViewModel.reload()`, in `TalosCore` — `MonitorViewModel.swift`, the `reload()`
hunk. This is the shape Rule 1 names as **asserted in prose**: the checked box is the only evidence,
and the diff does the opposite.

It is also two constraint violations, found by following the criterion into the diff rather than
reading the description:

- [Decision 33](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions)
  puts the parser in the adapter, which reports "counts and a model name" across the boundary, and
  [§ The adapter reports tokens as structured data](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-adapter-reports-tokens-as-structured-data)
  states the Monitor "never learns a log format".
- The orchestration boundary is **first** on
  [Contributing's ordered list](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints),
  so [`orchestration-boundary`](../../orchestration-boundary/SKILL.md) fires — and note `spec-guard`
  is green here, because reading a local file with `String(contentsOf:)` matches none of the patterns
  [Decision 11](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions)
  greps for. A green mechanical check is not the boundary having been reviewed.

### 2 — Criterion 4 is claimed and not met · Rules 1 and 3

The body checks criterion 4 and restates it as "the view refreshes as sessions progress", which is not
what the criterion says. The criterion says *from session events, with no polling timer*; the diff
uses `Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true)`. This is Rule 1's **adjacent, not
equal**: the restatement is true of the diff and the criterion is not.

[`gates-check`](../../gates-check/SKILL.md) fires on the timer.
[Foundations: States & Feedback § Nothing polls](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#nothing-polls):

> A live indicator updates from an **event** — a streamed token, a tool call, a session record — never
> from a timer that wakes to check. A spinner that costs CPU while idle fails a release gate.

### 3 — Criterion 2 is not met, and is not mentioned as unmet · Rule 1

`TableColumn("Cost")` renders a currency value with no estimate labeling.
[§ How cost is measured](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured)
requires cost be "An **estimate**, always labeled as such in the UI — **never presented as a bill**".
A bare currency column is the bill.

### 4 — Criterion 5 is claimed with nothing behind it · Rule 1

"VoiceOver labels added" appears in the body and no accessibility modifier appears in the diff. The
result column carries its meaning in an SF Symbol alone, which
[`gates-check`](../../gates-check/SKILL.md) covers via
[Foundations: Accessibility](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#reduce-transparency-and-reduce-motion) —
no information carried by color, material, or motion alone.

### 5 — The test verifies nothing · Rule 2

`loadsRows()` asserts `rows.isEmpty == false`. Ask Rule 2's question — what production change would
this catch? Nothing in the specified behavior: it passes whether counts are right or wrong, whether
cost is labeled, and whether the update came from an event or a timer. It is Rule 2's row "Asserts
only 'did not throw' or 'is not nil' for behavior specified as a value". It additionally depends on a
real session log on disk, which
[§ The suite installs nothing](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-suite-installs-nothing)
forbids. No criterion has a test that would fail if its behavior regressed.

### 6 — The PR body carries no verbatim binding line · Rule 5

The body links the Monitor Screen page and summarizes it — "tracks token cost, application performance,
and success rate" — rather than quoting a binding line. Per Rule 5 a summary of a section is not a
quote of it, and per
[§ Issues are never independent of the SPEC](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#issues-are-never-independent-of-the-spec),
"second sources of truth drift".

### 7 — Step 4 was not run, and this is where it would have fired · Rule 4

The diff contradicts three pages the issue never cites — the orchestration boundary, States &
Feedback, and Foundations: Accessibility — and the wiki was not changed. Rule 4's third row applies:
not mergeable. The point of the finding is *how* it was reached — Rule 4 requires checking the pages
the **diff** touches, not only the pages the issue cites, and every page here is one the issue never
mentioned.

---

## What the mechanical checks would have said

Title and scope match the Area (`monitor`), the branch prefix is `feat/`, and every required check is
green. A review that ran only Rule 6 would approve this PR. That is the failure mode
[§ Review is adversarial by default](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#review-is-adversarial-by-default)
describes:

> A review that only reads the PR description checks the author's summary, not the author's work — and
> the summary is written by the party with the least incentive to find the flaw.

---

## What the skill must not do

- **Not fix it.** Every finding above is reported; nothing is pushed to `feat/monitor-screen`
  (Rule 7).
- **Not decide the open questions.** Nothing here is a SPEC gap — each finding lands on a stated SPEC
  line. Had one not, Rule 8 applies and the part depending on it stays undecided.
- **Not close #900.** A passed review is not a close;
  [`create-issue`](../../create-issue/SKILL.md) closes the item against its own criteria, per
  [Decision 40](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions).
