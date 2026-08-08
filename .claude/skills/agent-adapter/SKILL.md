---
name: agent-adapter
description: Guards the agent adapter contract — the six capabilities every adapter declares, and the rule that adding an agent means writing one adapter and never touching Talos core. Use this BEFORE writing code on anything adapter-shaped: adding or changing an adapter for Claude Code, Gemini CLI, Codex CLI, or an Ollama-backed CLI; the adapter protocol or registry; spawning, streaming, or stopping an agent process; parsing agent output; detecting a tool call or a permission request; reporting tokens; or resolving an adapter name from `agents.yaml`. Also use it when a request would "add a hook in core for this agent", "special-case Gemini", "let the CLI handle its own approvals", "return the raw output and parse it upstream", or "skip the fixture and test against the real CLI" — those are the usual ways the contract gets broken. Enforces the six capabilities, that tool-call and permission-request events are distinct types, that tokens cross as structured data parsed inside the adapter, that stop() kills the whole process tree, that tests run on fixtures with no installed CLI, that the adapter holds no credential, and that a needed core change is reported as a core bug rather than worked around.
---

# Agent adapter

[Contributing](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#the-easiest-high-value-contribution-an-agent-adapter)
calls an adapter "**the easiest high-value contribution**". This skill exists because that claim is
load-bearing rather than encouraging: it is only true if the contract holds, and the contract is
broken by the *first* adapter, on behalf of the second.

**SPEC:** [Architecture: The Orchestration Boundary § Agent adapters](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#agent-adapters)
· [§ A tool call and a permission request are two events](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#a-tool-call-and-a-permission-request-are-two-events)
· [§ The adapter reports tokens as structured data](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-adapter-reports-tokens-as-structured-data)
· [§ Only the adapter layer spawns a process](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#only-the-adapter-layer-spawns-a-process)
· [Contributing § The easiest high-value contribution](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#the-easiest-high-value-contribution-an-agent-adapter)
· [Safeguards & Autonomy § Stop kills the tree](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree)
· [Engineering Standards § The suite installs nothing](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-suite-installs-nothing)
· [Project Library § AI Agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#ai-agent)

This skill **cites** the SPEC; it does not restate it. Rules live on the wiki pages linked here and
nowhere else — read the page, do not trust a summary in this file. Anything that looks like a rule
in this file without a link next to it is a bug in this file.

This is a **constraint skill**, not a workflow one. Per the
[skills table](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#if-you-contribute-with-an-ai-agent-use-the-skills),
constraint skills "guard a specific hard constraint and are run by whichever workflow skill is
active" — so it is invoked from `execute-issue`, `review-pr`, or
[`spec-driven-change`](../spec-driven-change/SKILL.md), and it does not own a
[dev-cycle](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle)
transition.

Run [`orchestration-boundary`](../orchestration-boundary/SKILL.md) alongside it, always. The adapter
layer is the one place Talos is *permitted* to spawn a process and read an agent's output, which makes
it the shortest path to the right of the agent — and that skill's
[red flags](../orchestration-boundary/SKILL.md) fire on the adapter surface by name.

---

## The rule this skill protects

From [§ Agent adapters](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#agent-adapters):

> **Adding an agent means writing one adapter, never touching Talos core.**

> That sentence constrains the six capabilities above, not merely the file count. Each rule below
> exists because an adapter can satisfy the list loosely and still force a core change on the next
> agent — and the second adapter is where that cost is discovered, by a contributor rather than by
> whoever wrote the first one.

The consequence, stated as an instruction to the contributor in
[Contributing](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#the-easiest-high-value-contribution-an-agent-adapter):

> If writing an adapter requires changing Talos core, that is a bug in Talos core — please open an
> issue rather than working around it.

Read that as two claims, because the second is the one that gets dropped. Needing a core change is a
**defect report**, and the work stops to file it. It is not a permission slip to make the change,
and it is not a reason to reshape the adapter around the gap.

---

## When this skill fires

Fire on the *surface*, not on the stated intent. An adapter change rarely announces that it is one —
it announces a new agent, a parsing fix, or a streaming improvement.

| Surface | Examples |
| --- | --- |
| **The protocol** | The adapter protocol or its associated types, any capability's signature, the event type a stream yields, the token report type |
| **An adapter** | Claude Code, Gemini CLI, Codex CLI, an Ollama-backed CLI, the stub, or a new one |
| **The registry** | Resolving an adapter by the name used in [`agents.yaml`](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#ai-agent), registration, defaults, fallbacks |
| **Process lifecycle** | Spawning, the environment or working directory handed to a child, streaming stdout/stderr, backpressure, exit handling, `stop()` |
| **Output interpretation** | Anything parsing agent output or session logs — tool calls, permission requests, token counts, model names, errors |
| **Core, on behalf of an agent** | Any change outside the adapter layer that exists because of a specific agent. This is the surface the rule is about, and it is the one that looks like ordinary work |
| **Adapter tests** | Fixtures, fakes, anything that would reach for an installed CLI or a live credential |

It also fires on **phrasing**, in an issue, a review comment, or a session instruction: "add a small
hook in core for this", "special-case Gemini for now", "let the CLI handle its own approvals",
"return the raw output and let the Monitor parse it", "just check if the binary is on PATH in core",
"skip the fixture, test against the real CLI". Each trades the contract for a shortcut. Treat the
first two as *core bug reports* per the rule above; the rest are rule violations below.

---

## Rule 1 — Six capabilities, no more and no fewer

The list is on the SPEC page and this file will not copy it: read
[§ Agent adapters](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#agent-adapters),
where "Each supported agent is a **thin adapter**" declaring six things. The identical list appears in
[Contributing](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#the-easiest-high-value-contribution-an-agent-adapter),
addressed to the contributor.

What each capability must guarantee — every row's requirement is the rule linked in it:

| Capability | What it must guarantee |
| --- | --- |
| **How to launch it** | The spawn happens here and [nowhere else in Talos](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#only-the-adapter-layer-spawns-a-process). An explicit working directory and environment, and [no credential in either](#rule-6--the-adapter-holds-no-credential). Nothing in core decides how a particular agent is invoked |
| **How to pass a prompt** | Talos [assembles the prompt](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#what-is-persistent-context-and-what-is-not) and the adapter transports it. The adapter does not edit, summarize, re-order, or append to it — a prompt the adapter rewrote makes [token overhead](https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable) unattributable and puts agent-specific prompt shaping outside the guideline set |
| **How to stream its output** | Incrementally, as it arrives, event-driven — [nothing polls](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#nothing-polls), and the console distinguishes [waiting, streaming, and running a tool](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#streaming-is-three-states-not-one), so the stream must carry enough to tell them apart. An adapter that buffers to completion has removed streaming from a console specified to show output "as it happens" ([Session Console](https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console#what-it-is)) |
| **How to detect a tool call or a permission request** | Two distinct event types — [Rule 2](#rule-2--a-tool-call-and-a-permission-request-are-two-event-types). Detection is round-trip: the SPEC has the adapter "[surface the request and carry back the decision the gate produced](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#a-tool-call-and-a-permission-request-are-two-events)", so the path that returns that decision belongs to this capability and is **not** a seventh. What it may not do is decide |
| **How to report token usage** | Structured data, parsed inside the adapter — [Rule 3](#rule-3--tokens-cross-as-structured-data-parsed-inside-the-adapter) |
| **How to stop it** | The process and every descendant, dead — [Rule 4](#rule-4--stop-guarantees-death-including-children) |

"No more" is also a rule. A seventh capability is agent-specific knowledge entering the contract that
*every* adapter must then satisfy, and the contributor writing the third adapter pays for it. If a
seventh looks necessary, that is a SPEC question — the six are specified — so it goes to a human, not
into the protocol.

Count capabilities, not methods. The six are obligations, and one of them can take more than one
function to discharge — the return path above is the case that comes up first. The test is whether a
member discharges one of the six or adds a seventh obligation, and reading it the other way turns
this rule into an argument about method count on a protocol nobody has written yet.

Two constraints on the protocol's shape, both from the contract rather than from taste:

- **No reference to any specific agent or model provider.** A protocol naming Claude Code has made
  agent knowledge core knowledge. It is also [flag 2](../orchestration-boundary/SKILL.md) territory
  if a provider comes with it.
- **The name is the one in `agents.yaml`.** Talos "declares the agent, its adapter, its MCP servers,
  and its allowed CLIs" there ([Project Library § AI Agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#ai-agent)),
  and everything under `.talos/` is plain text a user writes by hand
  ([where it lives](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives)).
  So an adapter name is a **public config contract** — renaming one breaks a user's committed file,
  the same reasoning the SPEC applies to the [action-type taxonomy](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#open-questions).

---

## Rule 2 — A tool call and a permission request are two event types

From [§ A tool call and a permission request are two events](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#a-tool-call-and-a-permission-request-are-two-events):

> **An adapter reports a tool call and a permission request as distinct, separately typed events —
> never as one.**

The reason they must be separated in the type system rather than by a flag or a string:

> Collapsing them removes the gate. Both arrive on the same stream in a similar shape, so a single
> event type makes the distinction a matter of which string the adapter happened to match, and the
> [interception that separates an orchestrator from a passthrough](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-common-misreading)
> becomes accidental rather than structural.

And the case that makes this a safeguards rule and not a modelling preference:

> **An agent CLI's own permission prompt is never a Talos approval.** An adapter surfaces the request
> and carries back the decision the gate produced; it never answers on the user's behalf, and it never
> launches its CLI in a mode that suppresses or pre-approves the CLI's own prompts.

- [ ] Two types, or two cases of one enum with distinct payloads. Not one type with
      `isPermissionRequest`, not a `kind: String`, not "a tool call whose name starts with…".
- [ ] A test per type, asserting a fixture that contains each produces the right one — and a test
      that a fixture containing **both** does not collapse them.
- [ ] The adapter never answers a permission prompt. No auto-confirm, no writing to the child's stdin
      to accept, and **no launch flag that suppresses or pre-approves prompts** — the SPEC names the
      flag case, and it is the one that looks like configuration rather than consent.
- [ ] A tool call reaches [the gate](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy)
      before the action runs. An adapter that streams a tool call straight through to the console has
      built the passthrough — run [`safeguards-review`](../safeguards-review/SKILL.md), which owns
      that case.
- [ ] The decision carried back is the **gate's**, and the
      [audit log](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules)
      names the actor honestly. An adapter-supplied answer produces a record naming a user who never
      decided — the same defect the SPEC rejects for
      [fail-closed denials](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed).
- [ ] An unrecognized event is not silently dropped or downgraded to plain output. The gate's own
      rule is that [an unrecognized call goes to the most restrictive tier](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#action-classification),
      "never to read" — an adapter that never emits the event denies the gate the chance to apply it.

---

## Rule 3 — Tokens cross as structured data, parsed inside the adapter

From [§ The adapter reports tokens as structured data](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-adapter-reports-tokens-as-structured-data):

> **Token usage crosses the adapter boundary as structured data — counts and a model name — never as
> text for Talos core to parse.**

> A Monitor that parsed agent output itself would make every new agent a core change, which
> contradicts the rule above. The log format is also the most volatile part of an agent CLI — it
> changes on that CLI's release schedule, not Talos's — so the code tracking it belongs in the one
> module a contributor is expected to rewrite.

The Monitor's side of the same rule is on
[Essential Tools § How cost is measured](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured):
"The Monitor knows counts and model names; it never knows a log format."

- [ ] The token report is a typed value. A string, a `[String: Any]`, or a raw log line handed
      upstream all fail — each moves the parse into core.
- [ ] No regex, JSON path, or log-shape knowledge for a specific agent exists outside the adapter.
      Grep the diff for it in core; this is the leak that arrives as a "small helper".
- [ ] The model name comes from the agent's own report, because
      [token counts are "Accurate — reported by the agent itself"](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured)
      and the name is what selects a price table. An adapter that infers or hardcodes it has made the
      estimate wrong in a way the UI will still label as an estimate.
- [ ] The adapter maps no prices and computes no cost. Cost is the Monitor's, against
      [price tables shipped with the app](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured),
      "**never presented as a bill**".
- [ ] No network call to obtain usage. This is [flag 5](../orchestration-boundary/SKILL.md) and
      [§ No proxying](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#no-proxying),
      which refuses interception by name even though it "would be exact".
- [ ] Talos-added [token overhead](https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable)
      stays measurable — a release gate at "< 5% of session tokens", which requires knowing what
      Talos added versus what the user's prompt would have cost.

**Log format drift is an open question, and it does not block this rule.** "Session log format drift"
is undecided in the
[Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#open-questions) — what
happens when a CLI update changes the format, "fail loudly, or degrade to token-less sessions". So an
adapter may parse a format; an adapter that *decides the degradation behavior* is settling the open
question and goes to a human first. Expect proxying to be re-proposed as the fix; it is already
refused.

---

## Rule 4 — `stop()` guarantees death, including children

From [Safeguards & Autonomy § Stop kills the tree](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree):

> **A surviving child is a failed stop, not a partial one.**

> An orphan keeps writing files, spending money, and holding locks after the user has been told the
> session is over — and it does it outside the [gate](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed),
> because the session that would have intercepted its next action no longer exists. That is worse
> than a session that never stopped: the user has stopped watching.

The base guarantee is [§ Rules](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules) —
"The user can **stop any running session immediately**, and stop means the process is killed" — and
the adapter owns it because
[only this layer spawns](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#only-the-adapter-layer-spawns-a-process):
"Whatever spawns must be able to kill."

- [ ] `stop()` is a guarantee, not a request. A cooperative signal an agent may ignore, a "graceful
      shutdown" with no enforcement, or a flag the read loop checks between chunks all fail —
      "immediately" is in the rule.
- [ ] **Children die too.** An agent CLI runs build tools, test runners, and package managers, so
      kill the tree, not the handle Talos holds.
- [ ] **A test asserts nothing survives**, rather than that a signal was sent. The SPEC states the
      assertion in those terms; a test that checks the call was made verifies the code, not the
      guarantee.
- [ ] Stop stays reachable while a session runs — [`⌘.`, never behind a confirmation](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Interaction-and-Keyboard#the-stop-guarantee-is-an-interaction-rule),
      because "A stop button that needs confirming is not a stop button."
- [ ] Stop works while the gate is **waiting** on a pending approval — that prompt
      [waits indefinitely with no timer](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-gate-fails-closed),
      so it is the state a session sits in longest, and the one where the user most wants out.
- [ ] Abnormal exit is a **typed failure** carrying the exit code and last output, attributed to the
      agent — Talos "**attributes it to the agent** and shows the agent's own output instead of
      paraphrasing it" ([Errors](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#errors)).
      A crash is not a denial and must not render as one
      ([denial is not failure](https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-States-and-Feedback#denial-is-not-failure)).
- [ ] Stopping leaves the session **recorded**, not vanished — the pipeline ends in a
      [session record and outcome](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model).

---

## Rule 5 — Tests run on fixtures; the suite installs nothing

From [Engineering Standards § The suite installs nothing](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-suite-installs-nothing):

> **No test requires an installed agent CLI, a real credential, or a network connection.** Adapter
> tests run against **recorded fixtures** — captured output of the real agent CLI, committed to the
> repo — and a fixture holding a token, a key, or a session identifier is a secret in git rather than
> a test asset.

Why it is a rule about the contract and not about test hygiene, from the same section:

> A suite that needs Gemini CLI installed and authenticated cannot verify the Gemini adapter on a CI
> runner or on the machine of a contributor who uses a different agent, so the tests that matter get
> skipped by whoever has the shortest path — and a skipped test is indistinguishable from a passing
> one on a green run.

- [ ] Every adapter test runs from a committed fixture. No `which`, no PATH probe, no "skip if not
      installed" — a conditional skip is the failure this rule names, not an accommodation of it.
- [ ] Fixtures are **real captured output**, not invented. A hand-written fixture tests the parser
      against the author's belief about the format, which is exactly the belief under test.
- [ ] Fixtures carry **no secret** — no token, key, or session identifier. Secrets live "only in the
      **macOS Keychain**" ([Project Library](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives)),
      and a fixture is committed, so this is a
      [secret-scanning](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards) matter
      as much as a SPEC one.
- [ ] Fixtures cover the events the rules above require: a tool call, a permission request, both
      together, a token report, an abnormal exit, and malformed output.
- [ ] Tests read as statements of the SPEC — the reason Swift Testing was chosen, so a `@Test`
      "keeps a test readable as a statement of the spec it verifies"
      ([Toolchain](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#toolchain)).
- [ ] No network. Also [flag 5](../orchestration-boundary/SKILL.md), which holds
      [in a test target too](../orchestration-boundary/SKILL.md) — DoD #11 says "anywhere in the
      Talos codebase."

---

## Rule 6 — The adapter holds no credential

The adapter is where a credential would be most convenient, because it is the thing launching a
process that needs one. It is therefore the rule most likely to be broken with good intentions.

From [§ Consequences that must hold at all times](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#consequences-that-must-hold-at-all-times):

> - Talos holds **no** model API keys. Agent CLIs use their own existing authentication.

And [Project Library § AI Agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#ai-agent):

> Talos declares the agent, its adapter, its MCP servers, and its allowed CLIs. It does **not** hold
> the credentials — the agent CLI uses its own existing authentication.

- [ ] The adapter reads, stores, and forwards **no** model credential. Not from the environment, not
      from the Keychain, not from `agents.yaml` — which holds "references to secrets, never secrets"
      ([where it lives](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives)).
- [ ] **The spawned environment contains no model API key**, and a test asserts it. The child
      environment is the specific hole: passing a key through is not "holding" one in the author's
      reading, and it is the third consequence broken.
- [ ] The adapter does not log, echo, or include a credential in an error, a session record, or a
      fixture. A record the user can read is a record a secret must not be in.
- [ ] **Non-model** credentials — a GitHub token, for instance — are still not the adapter's to
      forward on its own initiative. They live in the Keychain, they are referenced rather than
      inlined, and secret access is
      [never allowlistable](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable).
- [ ] The adapter opens no connection to a model provider and drives no agent loop. The adapter runs
      a CLI that does both — [flags 1, 2, 5, and 6](../orchestration-boundary/SKILL.md).

---

## Rule 7 — A needed core change is a core bug, reported not worked around

The binding line, again, because this is the rule the whole skill exists for
([Contributing](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#the-easiest-high-value-contribution-an-agent-adapter)):

> If writing an adapter requires changing Talos core, that is a bug in Talos core — please open an
> issue rather than working around it.

**No Talos core file is modified by adapter work.** When one appears to be needed, the deliverable is
the report: state what the adapter could not express, which capability it belongs to, and what core
would have to offer. Then stop that part of the work.

What this rules out — each of these is the violation, and none of them looks like editing core:

| Shape | Why it is the same violation |
| --- | --- |
| A "small hook" in core for this agent | Agent knowledge in core. The next adapter needs a different hook, and the claim that adding an agent touches one file is now false |
| A `switch` on the agent's name anywhere outside the adapter | The registry resolves a name to an adapter; anything else branching on it has made core agent-aware |
| Widening a core type to fit this agent — an extra optional field, a looser enum | The protocol now carries one agent's shape, and every other adapter inherits a field it must ignore |
| Returning raw output for core to interpret | Rule 3. The parse moved to core; the core change is just deferred to whoever writes the parser |
| Reaching around the protocol — core reading a file the adapter wrote, or a shared global | The dependency exists; it is only untyped. This is the same violation plus concealment |
| Putting non-adapter code **inside** the adapter module so the check passes | Inverts the rule. A spawn or a git helper parked in the adapter layer is [a defect "whatever it is for"](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#only-the-adapter-layer-spawns-a-process) |

Two things are **not** violations, and confusing them wastes the rule's credibility: **registering**
the new adapter where the registry expects it, and a
[SPEC change](../spec-driven-change/SKILL.md) that a human decided — which then makes the core change
sanctioned work with a decision behind it, not an adapter workaround.

The stub adapter is the working reference for all of this: **[#55](https://github.com/CalixtoTheBugHunter/talos/issues/55)**
proves the abstraction with a compile-only stub, and its acceptance criteria include a test that
"asserts zero files outside the adapter module were needed" and that "The stub is documented as the
reference for contributors writing Gemini CLI, Codex CLI, or Ollama adapters." Read the stub before
writing an adapter, and read it as the executable form of this rule — if the stub needed a core file,
this skill's own claim is already false. Until #55 lands, the assertion is checked by reading.

---

## Worked example — a Gemini adapter that needs one small core change

The verification case for this skill. A PR titled *"feat(adapter): add Gemini CLI support"* adds
`Sources/TalosAdapters/Gemini/GeminiAdapter.swift` implementing all six capabilities. Gemini's CLI
reports usage in a shape the existing token type cannot hold, so the PR adds an optional
`rawUsage: String` field to the core token report and a `if agentName == "gemini"` branch in the
Monitor to parse it. It builds, its tests pass against a real Gemini CLI on the author's machine, and
the feature is real and wanted — [Contributing](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#the-easiest-high-value-contribution-an-agent-adapter)
lists Gemini CLI under "Wanted".

**Rejected.** How the skill gets there:

1. **Fires** — the diff adds an adapter and touches the token report type. Two surfaces, before any
   argument about whether the core change is small.
2. **Rule 7 hits on the mechanism.** Two core files changed for one agent: a widened core type and a
   name branch. Both rows are in the table above. Note the PR is honest about it and calls it small —
   size is not the criterion, and the rule's own remedy is "open an issue rather than working around
   it."
3. **Rule 3 hits independently.** `rawUsage: String` is text crossing the boundary for core to parse,
   and the Monitor branch is the log-format knowledge the SPEC puts inside the adapter: "The Monitor
   knows counts and model names; it never knows a log format." The optional field is what makes the
   violation look additive rather than breaking.
4. **The two findings are the same finding.** The core change is needed *because* the parse was left
   undone in the adapter. So the fix is not "get the core change approved" — it is to parse Gemini's
   shape inside the Gemini adapter and report the structured type core already has. The core change
   disappears rather than being negotiated.
5. **Rule 5 — the tests fail whatever happens to Rules 3 and 7.** They need Gemini CLI installed and
   authenticated, so CI cannot run them and no contributor without Gemini can. Per the SPEC, "the
   tests that matter get skipped by whoever has the shortest path." They are replaced by committed
   fixtures of real captured Gemini output.
6. **Then check the rest, because a rejected PR is still reviewed in full.** Are the tool-call and
   permission-request events distinct (Rule 2), does Gemini's CLI have its own approval prompt the
   adapter might be answering or suppressing by flag (Rule 2), does `stop()` kill the tree that
   Gemini's own tool calls spawn (Rule 4), and is a key reaching the child's environment (Rule 6)?
7. **Verdict and the path.** Reject. Parse inside the adapter, revert both core files, ship fixtures,
   and — if the structured type genuinely cannot represent Gemini's usage — that is the core bug: file
   it under Rule 7 with what the adapter could not express, and let it be decided as a SPEC change
   rather than absorbed as a field.

The shape to reuse: **the skill rejects the core change before it evaluates whether the core change
is reasonable**, then finds the adapter-side omission that made it look necessary. A PR is not rescued
by the agent being on the wanted list, by the core change being small and additive, or by tests that
pass on the author's machine.

---

## SPEC gaps

Do not fill a gap with an assumption; raise it for a human decision and the
[Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log), per
[`spec-driven-change` § Escalating a SPEC gap](../spec-driven-change/SKILL.md). Known gaps on this
surface:

| Gap | Why it is a gap |
| --- | --- |
| **Session log format drift** | An [open question](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#open-questions): "What happens when a CLI update changes that format — fail loudly, or degrade to token-less sessions?" An adapter may parse a format; one that decides the *degradation* behavior settles the question. See Rule 3 |
| **Keychain reference syntax** | `agents.yaml` holds "references to secrets, never secrets" ([Project Library](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives)) and no page specifies the reference format. The adapter is where a reference gets resolved, so it is where the shape gets decided by accident. It is a public config contract users write against |
| **Multi-agent orchestration** | A project "may configure **more than one agent**, and Talos orchestrates which one handles which job" ([§ Agent adapters](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#agent-adapters)), and no page states *how* one is selected per job. An adapter change that assumes a selection rule has decided it |

A change that needs one of these answers moves to **Blocked** — which is
[a real destination, not a failure to try harder](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#the-dev-cycle) —
and the gap goes to the Decision Log before the code that depends on it. Everything in the change
that does not depend on it continues.

---

## Checklist before marking a change ready

- [ ] [§ Agent adapters](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#agent-adapters)
      was read in this session, from the wiki, before the first edit — and so was the stub adapter.
- [ ] Exactly the six SPEC capabilities, each guaranteeing what the table above requires. No seventh
      *obligation* — the gate's return path discharges the fourth rather than adding one.
- [ ] The protocol names no specific agent or provider, and the adapter's name matches `agents.yaml`.
- [ ] Tool call and permission request are **distinct types**, each with its own test plus one for a
      fixture containing both.
- [ ] The adapter never answers, suppresses, or pre-approves the CLI's own permission prompts, and the
      decision it carries back is the gate's.
- [ ] Tokens cross as **structured data**; no agent log-format knowledge exists outside the adapter;
      the adapter computes no cost and makes no network call.
- [ ] `stop()` kills the process **and its children**, asserted by a test that nothing survives — and
      it works while a pending approval waits.
- [ ] Abnormal exit is a typed failure attributed to the agent, and the session is still recorded.
- [ ] Every adapter test runs from a **committed, real-capture fixture**. Nothing probes for an
      installed CLI, nothing skips conditionally, no fixture contains a secret.
- [ ] The adapter holds and forwards **no credential**, and a test asserts the spawned environment has
      no model API key.
- [ ] **No Talos core file was modified.** Where one seemed necessary, it was reported as a core bug
      with what the adapter could not express — not worked around, not widened, not branched on.
- [ ] [`orchestration-boundary`](../orchestration-boundary/SKILL.md) was run, and
      [`safeguards-review`](../safeguards-review/SKILL.md) too if the change touches the gate's events.
- [ ] Every gap hit sent the item to **Blocked** and went to a human and the Decision Log — none was
      assumed.
