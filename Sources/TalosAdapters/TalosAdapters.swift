// The agent adapter layer — the only module permitted to spawn a subprocess,
// which `spec-guard` check 4 enforces against every other module by path.
// A type added here rather than under a concrete adapter's own subdirectory
// becomes part of the contract every adapter implements, and is checked for
// agent and provider names by `NoAgentOrProviderReferenceTests`.
// § Only the adapter layer spawns a process —
// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
