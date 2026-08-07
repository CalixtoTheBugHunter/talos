---
name: orchestration-boundary
description: Guards the single most important architectural rule in Talos — Talos orchestrates agents and never calls a model itself. Use this BEFORE writing code whenever a change touches networking (any HTTP client, URLSession, socket, hostname, or endpoint), agent adapters, MCP or CLI configuration, credentials (API keys, tokens, Keychain, environment variables passed to a child process), subprocess spawning, cost/token parsing, or connectors and board integrations. Also use it when a request would have Talos "ask the model", "call the API", "summarize", "embed", "classify", or "proxy the agent's traffic" — those phrasings are the usual way the boundary gets crossed. Lists the concrete red flags, states the scope rule that a feature requiring a direct model call is out of scope and must be declined rather than built, and names the one module allowed to spawn a subprocess.
---

# Orchestration boundary

[Contributing](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints)
lists this constraint **first**, in a list ordered by "how often they get violated by accident".
That ordering is the reason this skill exists: the rule is not hard to understand, it is hard to
*notice* you are breaking.

**SPEC:** [Architecture: The Orchestration Boundary](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary)
· [MVP Definition of Done § Notes on the harder criteria](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#notes-on-the-harder-criteria)
· [Contributing § Before you write code](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints)

This skill **cites** the SPEC; it does not restate it. Rules live on the wiki pages linked here and
nowhere else — read the page, do not trust a summary in this file. Anything that looks like a rule
in this file without a link next to it is a bug in this file.

Run [`spec-driven-change`](../spec-driven-change/SKILL.md) first — it is the entry point, and this
skill is one of the constraint guards it dispatches to.

---

## The rule

From [Architecture: The Orchestration Boundary](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary),
which opens by calling itself "the **most important architectural rule in Talos**. Everything else
follows from it":

> ## Talos is a bridge between user and AI Models for agentic software development.

> The connected AI agents perform every MCP and CLI action. Talos orchestrates that work and acts
> as the bridge between the user and the agents.

The negative form of the same rule, from
[Contributing § Before you write code](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints):

> **[The orchestration boundary](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary)** — Talos never talks to
> a model API and never implements an agent loop. No API clients, no MCP client, no API keys. If a
> feature can only be built by Talos calling a model directly, that feature is out of scope.

And the geometric form — the one worth holding in your head while reading a diff:

> Talos is on the **left of the agent, never to the right of it.** The agent CLI owns the model
> call, the agent loop, and its own authentication. Talos never sees the provider.

Read the [message-flow diagram](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#how-a-message-actually-flows-into-talos-workflow)
on that page before reviewing a change. A change is a violation when it moves Talos to the right of
the agent, whatever it is called in the PR title.

---

## When this skill fires

Any change touching a cell in this table. Fire on the *file and dependency surface*, not on intent —
nobody writes a PR titled "add a model API client."

| Surface | Examples |
| --- | --- |
| **Networking** | Any HTTP client, `URLSession`, `URLRequest`, sockets, a hostname or URL literal, a new networking dependency, retry/backoff logic, a "provider" or "endpoint" type |
| **Adapters** | Anything under the [adapter](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#agent-adapters) surface, subprocess spawning, streaming, output parsing, [token reporting](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen) |
| **MCP / CLI config** | Anything reading or writing `agents.yaml`, MCP server declarations, allowed-CLI lists ([Project Library § AI Agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#ai-agent)) |
| **Credentials** | API keys, tokens, Keychain access, `.env`, the environment dictionary handed to a child process, anything named `auth`, `secret`, or `bearer` |
| **Cost / monitoring** | [Monitor Screen](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen) work, price tables, anything that would be "more accurate" by intercepting traffic |
| **Connectors / board** | GitHub, Jira, monitoring, deployment, or test integrations ([Project Library § Connectors](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#connectors)) |

It also fires on **phrasing**, in an issue or a session instruction: "have Talos ask the model",
"call the API directly", "just embed it", "summarize this locally", "proxy the agent's traffic",
"we need our own key for that". Each is a request to move Talos to the right of the agent. Treat it
as a request to change the SPEC — see *When the request itself crosses the boundary*.

---

## The four consequences that must hold at all times

Quoted verbatim from
[Architecture: The Orchestration Boundary § Consequences that must hold at all times](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#consequences-that-must-hold-at-all-times).
That section's own framing: "These are testable. Item 11 of the
[MVP Definition of Done](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done)
checks them."

> - Talos ships **no** API client for Anthropic, Google, Amazon Bedrock, OpenAI, or Ollama.
> - Talos ships **no** MCP client of its own. MCP servers are configured *for the agent*; Talos
>   writes that configuration and reads its results.
> - Talos holds **no** model API keys. Agent CLIs use their own existing authentication.
> - **If a feature can only be built by Talos calling a model directly, that feature is out of
>   scope.**

"At all times" is literal. There is no branch, no feature flag, no debug build, and no test fixture
in which one of the four is suspended. A mock provider client in a test target is still a provider
client in the codebase, and
[DoD #11](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done) says
"anywhere in the Talos codebase."

The enforcement mechanism, from
[MVP Definition of Done § Notes on the harder criteria](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#notes-on-the-harder-criteria):

> **#11 is checkable by grep.** It is the enforcement mechanism for
> [the orchestration boundary](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary) — the rule that everything
> else in Talos depends on. If this criterion fails, the architecture has drifted and the fix is not
> cosmetic.

That grep is the **spec-guard** CI stage
([Engineering Standards § CI pipeline order](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order),
[Decision Log #11](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions)).
This skill runs **before** the code exists; spec-guard catches what got written anyway. Do not treat
a green spec-guard as permission — it greps for known shapes, and a novel violation passes it.

---

## Red flags

Any hit is a **stop**, not a comment on the PR. Each row is one of the four consequences made
concrete.

| # | Red flag | What it looks like in a diff |
| --- | --- | --- |
| 1 | **Model provider hostnames** | `api.anthropic.com`, `generativelanguage.googleapis.com`, `bedrock*.amazonaws.com`, `api.openai.com`, `localhost:11434` / any Ollama endpoint — in code, config, `Info.plist`, entitlements, or a test fixture |
| 2 | **Model SDK imports** | `import Anthropic`, an `openai-swift` / `google-generative-ai` / `aws-sdk-swift` Bedrock package in `Package.swift` or the Xcode project, a vendored provider client |
| 3 | **MCP client dependencies** | An MCP *client* or SDK as a Talos dependency, a `JSONRPC`/stdio transport Talos itself drives, code that connects to an MCP server rather than declaring one for the agent |
| 4 | **API-key handling** | A key-shaped literal, `ANTHROPIC_API_KEY` and friends read or written by Talos, a Keychain item for a *model* provider, a model key placed into a spawned process's environment |
| 5 | **Any HTTP client in Talos core** | `URLSession`, `URLRequest`, a socket, or a networking package reached from the core module graph — regardless of which host it points at |
| 6 | **An agent loop in Talos** | A `while` loop over model turns, tool-call dispatch, prompt→response→tool→repeat, retry-on-refusal, token-by-token assembly. [Division of responsibility](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#division-of-responsibility) puts "The agent loop and reasoning" in the agent's column |
| 7 | **Proxying the agent's traffic** | A local proxy, `HTTPS_PROXY` injected into the agent's environment, TLS interception, a "more accurate cost" MITM |

Flag 5 is the broadest and the most likely to be argued with. It is stated on the SPEC page itself:

> If you find yourself reaching for an HTTP client, the model has drifted.

Flag 7 is refused by name in
[Essential Tools § No proxying](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#no-proxying),
including the reason it keeps getting proposed and why it is still refused:

> Talos does **not** proxy agent traffic. Intercepting the agent's own connection would be exact,
> but it is fragile across CLI versions and creates a credential surface Talos will not own — see
> [the orchestration boundary](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary).

Note what that sentence concedes: the violating design **works better** on the metric it targets.
"It is more accurate" is therefore never a counter-argument here; the SPEC already weighed accuracy
against owning a credential surface and chose.

### What is not a red flag

A guard that cries wolf gets switched off. These are SPEC-sanctioned, and confusing them with the
above wastes the reviewer's trust:

| Allowed | The SPEC line that allows it |
| --- | --- |
| Writing MCP server / CLI declarations *for the agent* | "MCP servers are configured *for the agent*; Talos writes that configuration and reads its results" ([boundary](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#consequences-that-must-hold-at-all-times)) |
| Parsing the agent's own session logs for tokens and cost | [Essential Tools § How cost is measured](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#how-cost-is-measured) — parse logs, map to shipped price tables, no network call. The parse belongs [inside the adapter](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-adapter-reports-tokens-as-structured-data), which reports structured data |
| Spawning the agent CLI as a child process | "Talos hands prompt + context to the CONNECTED AGENT CLI (a process it spawns)" ([flow, step 3](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#how-a-message-actually-flows-into-talos-workflow)) — and only from the one module below |
| **Non-model** credentials in the Keychain | [Project Library § Where it lives](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives) — "API keys and tokens live only in the **macOS Keychain**", and `agents.yaml` holds "references to secrets, never secrets". Model keys stay excluded by the third consequence |
| In-app auto-update over the network | [Technology & Distribution § Decisions](https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution#decisions) — "Sparkle-style in-app auto-update, user-controlled". A sanctioned network client, outside core, for a non-model purpose. Not a precedent for any other network call |

Two things that look like exceptions and are not: **telemetry** is "**None.** No analytics, no
phone-home, no crash upload without explicit opt-in"
([Technology & Distribution](https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution#decisions)),
and **connector/board traffic** is the agent's work, not Talos's — "The connected AI agents perform
every MCP and CLI action." Reaching for an HTTP client to move a board item is flag 5 wearing a
different hat.

---

## The scope rule

The fourth consequence is not a preference to be traded off against a roadmap:

> **If a feature can only be built by Talos calling a model directly, that feature is out of
> scope.**

> That last line is a scope rule, not a preference. It is the cheapest way to keep Talos small,
> keep it out of the credential business, and keep token spend on the user's own subscription where
> they can see it.

**The correct response is to say the feature is out of scope — not to build it, and not to build a
narrower version of it that still crosses the boundary.** Declining is the deliverable. Say which
part is out of scope, cite the consequence it hits, and — if there is a version reachable through
the agent — offer that instead.

What this rules out, specifically:

- Building it "just for now", behind a flag, or "temporarily until the adapter lands."
- Shrinking it to a "tiny" call — one embedding, one classification, one summary. Size is not the
  criterion; who makes the call is.
- Routing it through a helper, a test target, or a dependency so the grep misses it. That is the
  same violation plus concealment.
- Treating the feature as blocked pending a decision. It is not blocked; the SPEC already answered.

This is a hard constraint, and
[Contributing](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#before-you-write-code-read-the-constraints)
states what happens to code that violates one: "Talos has **hard constraints** that are rejected
rather than negotiated. A PR that violates one will be closed regardless of code quality."

It is also *why Talos exists* rather than an implementation detail —
[Vision & Principles § Talos is not an AI](https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#talos-is-not-an-ai):

> Talos does not replace Claude, GPT, Gemini, or free models from Ollama. Talos connects to an
> existing AI agent, manages those connections, and creates automations and notifications for the
> user.

---

## The correct alternative: configure the agent, then read its results

Every feature that feels like it needs a model call has the same shape available to it. This is the
second consequence generalized — "MCP servers are configured *for the agent*; Talos writes that
configuration and reads its results."

```
❌ Talos → model provider                     (out of scope)
✅ Talos writes config + assembles context
     → agent CLI does the work
       → Talos reads the result
```

Three steps, in the order the
[session pipeline](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model)
already runs them:

1. **Configure** — declare the agent, its adapter, its MCP servers, and its allowed CLIs in
   `agents.yaml`. Per [Project Library § AI Agent](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#ai-agent):
   "Talos declares the agent, its adapter, its MCP servers, and its allowed CLIs. It does **not**
   hold the credentials — the agent CLI uses its own existing authentication."
2. **Assemble and hand off** — build the prompt from the
   [Project Library](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library) and the
   guideline set, then hand it to the agent CLI. What may and may not be assembled is a table on the
   SPEC page: [What is persistent context, and what is not](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#what-is-persistent-context-and-what-is-not) —
   "Model API keys — Talos holds none" sits in the *never leaves Talos* column.
3. **Read the results** — parse the agent's output and its session logs. This is how the
   [Monitor Screen](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen)
   gets tokens and cost with no network call, and it is the pattern for everything else.

Where a capability is genuinely missing, the answer is an
[**adapter**](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#agent-adapters),
never a client. "**Adding an agent means writing one adapter, never touching Talos core.**" And per
[Contributing](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing#the-easiest-high-value-contribution-an-agent-adapter):
"If writing an adapter requires changing Talos core, that is a bug in Talos core — please open an
issue rather than working around it." For adapter work itself, use
[`agent-adapter`](../agent-adapter/SKILL.md), which owns the six capabilities and that report.

---

## The common misreading

From [§ The common misreading](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-common-misreading):

> The most frequent mental-model error is collapsing "agent CLI" and "model" into one box:

| ❌ Wrong | ✅ Right |
| --- | --- |
| `You → Talos → AI model → Talos → You` | `You → Talos → agent CLI → model provider` |

> Both diagrams look the same from the user's chair, which is exactly why the error is easy to make.
> But the wrong one implies Talos holds an API key and speaks a provider protocol — and building it
> that way violates [MVP Definition of Done](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done) item 11, which is checkable by
> grep. If you find yourself reaching for an HTTP client, the model has drifted.

Two boxes, and the difference between them is invisible in the UI and total in the code. When a
feature request describes the user-visible behavior, it is describing something both diagrams
satisfy — so the request never tells you which one to build. Default to the right-hand one.

The SPEC names a second misreading on the same page, and a change to the session pipeline can break
it: treating the [Safeguards](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy)
gate as part of the agent's reply. "It is not — it **interrupts** the reply… That interception is the
difference between an orchestrator and a passthrough." A change that streams a tool call straight
through has removed the thing that makes Talos an orchestrator. Use the `safeguards-review` skill
there.

---

## The one module allowed to spawn a subprocess

Talos runs [unsandboxed](https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution#why-unsandboxed-is-safe-here)
precisely so it can spawn agent CLIs, so "can it spawn a process" is not the question — "which
module may" is.

From [§ Only the adapter layer spawns a process](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#only-the-adapter-layer-spawns-a-process):

> **Only the agent adapter layer may spawn a subprocess. No other part of Talos may.** Spawning is an
> adapter capability ("how to launch it", above), and confining it to one place is what keeps
> [MVP DoD](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done) item 11 checkable by the compiler rather than remembered by a
> reviewer.

> - A spawn anywhere outside the adapter layer is a **defect**, whatever it is for.

Concretely, that layer is the **`TalosAdapters`** module. The SPEC states the rule as a *layer* so a
Swift-level rename cannot make it wrong; the module name is fixed by
[#36](https://github.com/CalixtoTheBugHunter/talos/issues/36) — "an explicit statement of which
module may spawn a subprocess (only `TalosAdapters`)" — and
[Decision 18](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions)
records both halves. So check the layer first; if a spawn is outside it, the module name is not the
argument.

A spawn outside it will also fail spec-guard once
[#24](https://github.com/CalixtoTheBugHunter/talos/issues/24) lands — "It asserts only the adapter
module spawns subprocesses." Until #36 lands there is no module graph to check against, so until
then the rule is checked by reading rather than by the compiler. That is a reason to check it, not a
grace period.

The SPEC pairs the rule with its consequence — whatever spawns must be able to kill:

> - Whatever spawns must be able to kill: the user can
>   [stop any running session immediately, and stop means the process is killed](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules) —
>   [the whole process tree](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree), not the process Talos holds a
>   handle to.

A spawn site that cannot guarantee death is a boundary problem and a
[Safeguards](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#rules)
problem at once. The tree is the binding scope —
"[a surviving child is a failed stop, not a partial one](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#stop-kills-the-tree)" —
and for adapter work [`agent-adapter`](../agent-adapter/SKILL.md) owns it.

---

## Worked example — a PR that adds an HTTP client

The verification case for this skill. A PR titled *"feat(monitor): fetch live model pricing"* adds
`Sources/TalosCore/Networking/HTTPClient.swift` with a `URLSession` wrapper, and one caller that
GETs a pricing endpoint. No provider hostname, no SDK, no API key. It builds, it is tested, and the
feature is real: shipped price tables go stale.

**Rejected.** How the skill gets there:

1. **Fires** — the diff touches *Networking*, and adds a URL literal and a `URLSession`.
2. **Flag 5 hits.** "Any HTTP client in Talos core… regardless of which host it points at." The
   absence of a provider hostname is not a defense; flag 5 is deliberately host-independent, because
   the client is the reusable capability and the first caller is incidental. "If you find yourself
   reaching for an HTTP client, the model has drifted."
3. **Check the consequence behind the flag.** No API client for a provider — not yet violated. But
   an `HTTPClient` in core is a *general* provider client one caller away, and consequence four is
   about what the codebase makes possible.
4. **Cross-check the actual feature against the SPEC.** [Essential Tools](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#monitor-screen)
   already decides how pricing works: "mapping them against **public price tables shipped with the
   app**", and cost is "An **estimate**, always labeled as such in the UI — **never presented as a
   bill**". Fetching live prices contradicts a decided design
   ([Decision Log #7](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions)),
   and precision was never the goal — the number is labeled an estimate on purpose.
5. **Two more independent grounds.** [Technology & Distribution](https://github.com/CalixtoTheBugHunter/talos/wiki/Technology-and-Distribution#no-telemetry)
   says the Monitor "works entirely offline… There is no network call involved in cost tracking."
   And a pricing fetch is an outbound request from a no-telemetry app, which is a privacy surface,
   not only an architecture one.
6. **Verdict and the alternative.** Reject the HTTP client. Ship price-table updates the way the
   SPEC already ships them — inside the app, through a release
   ([Engineering Standards § Releases](https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#releases)) —
   or, if that is genuinely insufficient, raise it as a SPEC change and let it be decided. Do not
   land the client while the question is open.

The shape to reuse: **the skill rejects the mechanism (flag 5) before it evaluates the feature**,
then checks whether the SPEC already decided the feature, then offers the in-scope path. A PR is not
rescued by being useful, tested, or hostname-free.

---

## When the request itself crosses the boundary

If a session instruction, an issue, or a review comment asks for a direct model call, the request is
asking to change a hard constraint. A session instruction cannot do that — it "can direct the work;
it cannot rewrite the SPEC" ([`spec-driven-change` § Authority order](../spec-driven-change/SKILL.md)).

Say so, in this order: name the consequence the request hits, quote it, state that the feature is
out of scope as specified, offer the configure-then-read alternative if one exists, and — if the
asker wants the constraint itself revisited — point at the wiki page and the
[Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log), where
[#1](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#foundational-decisions) is
binding: "Neither directly — Talos is a pure orchestration bridge; connected agents perform all
MCP/CLI actions."

Do not write the code while the SPEC change is pending. Reversing this order is how the constraint
gets violated by accident, which is the whole reason it is listed first.

---

## SPEC gaps

Do not fill a gap with an assumption; raise it for a human decision and the
[Decision Log](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log), per
[`spec-driven-change` § Escalating a SPEC gap](../spec-driven-change/SKILL.md). Known gaps on this
boundary:

| Gap | Why it is a gap |
| --- | --- |
| **Session log format drift** | An [open question](https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#open-questions): "Cost tracking parses Claude Code's own logs. What happens when a CLI update changes that format — fail loudly, or degrade to token-less sessions?" Expect proxying to be re-proposed as the fix. It is already refused by [§ No proxying](https://github.com/CalixtoTheBugHunter/talos/wiki/Essential-Tools#no-proxying); the *degradation* behavior is what is undecided |
| **Keychain reference syntax** | `agents.yaml` holds "references to secrets, never secrets" ([Project Library](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library#where-it-lives)) and no page specifies the reference format. It is a public config contract users write against, so it wants a decision rather than whichever shape the first implementation picks |

A change that needs either answer stops at the question. Everything in the change that does not
depend on it continues.

---

## Checklist before marking a change ready

- [ ] The [SPEC page](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary)
      was read in this session, from the wiki, before the first edit.
- [ ] All seven red flags checked against the actual diff — including test targets, fixtures,
      `Package.swift`, the Xcode project, `Info.plist`, and entitlements.
- [ ] No new networking dependency or HTTP client is reachable from Talos core.
- [ ] No model API key is read, written, stored, or placed in a spawned process's environment.
- [ ] Any subprocess spawn is in `TalosAdapters`, and its `stop()` kills the process.
- [ ] MCP and CLI work *declares* servers for the agent; nothing in Talos connects to one.
- [ ] Talos is still on the left of the agent in the changed flow — no agent loop, no proxy, no
      passthrough around the Safeguards gate.
- [ ] Anything out of scope was **declined and named as out of scope**, not built smaller.
- [ ] Every gap hit went to a human and the Decision Log — none was assumed.
