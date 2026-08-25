# Architecture

The Talos Swift package is split into seven modules so that
[the orchestration boundary](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary)
is enforced by the compiler, not only by review. This file documents the module graph
`Package.swift` declares; a test in `Tests/TalosCoreTests/ModuleDependencyGraphTests.swift` asserts
the two stay in agreement.

This file is not the SPEC. The wiki is — see
[Architecture: The Orchestration Boundary](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary)
and [Contributing](https://github.com/CalixtoTheBugHunter/talos/wiki/Contributing). What follows is
this repository's implementation of that boundary: which module is which, and which one may spawn a
subprocess.

## Modules

| Module | Depends on | Role |
| --- | --- | --- |
| `TalosCore` | — | Shared types and cross-cutting foundations with no dependency of their own. |
| `TalosPersistence` | `TalosCore` | SQLite + plain-text persistence under `.talos/`. |
| `TalosProjectLibrary` | `TalosCore`, `TalosPersistence`, `Yams` | The five [Project Library](https://github.com/CalixtoTheBugHunter/talos/wiki/Project-Library) parts — AI Agent, Spec Drive, Connectors, Board, Safeguards config — read from and written to `.talos/`. `Yams` (MIT, no dependencies of its own) parses and serializes the `.yaml` files under `.talos/`. |
| `TalosSafeguards` | `TalosCore` | The tiered, deny-by-default [Safeguards gate](https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy). |
| `TalosAdapters` | `TalosCore` | The [agent adapter layer](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#agent-adapters). **This is the only module permitted to spawn a subprocess.** |
| `TalosOrchestration` | `TalosCore`, `TalosProjectLibrary`, `TalosSafeguards`, `TalosAdapters`, `TalosPersistence` | The [shared session pipeline](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#the-shared-session-model) that assembles context, runs the gate, and drives an adapter. |
| `TalosUI` | `TalosOrchestration` | SwiftUI surfaces. |

## Which module may spawn a subprocess

**Only `TalosAdapters` may spawn a subprocess. No other module may.** Per
[§ Only the adapter layer spawns a process](https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary#only-the-adapter-layer-spawns-a-process):

> Only the agent adapter layer may spawn a subprocess. No other part of Talos may. Spawning is an
> adapter capability ("how to launch it", above), and confining it to one place is what keeps
> [MVP DoD](https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done) item 11
> checkable by the compiler rather than remembered by a reviewer.

## What the graph structurally prevents

No module depends on Foundation's URL loading system for a model provider, an MCP client SDK, or any
model SDK — the dependency lists above are exhaustive, and none of them names such a dependency.
Because `TalosCore` has no dependencies at all, nothing added to `TalosCore` can reach a networking
client through the graph without a new edge appearing in this table and in `Package.swift` — the
change [`orchestration-boundary`](.claude/skills/orchestration-boundary/SKILL.md) is run against
before it lands.
