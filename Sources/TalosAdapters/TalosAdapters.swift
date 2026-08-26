// The agent adapter layer — the only module permitted to spawn a subprocess.
// Deliberately empty: the actual types live in this target's other files;
// this one exists only so the module graph in `ARCHITECTURE.md` builds.
// § Only the adapter layer spawns a process —
// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
