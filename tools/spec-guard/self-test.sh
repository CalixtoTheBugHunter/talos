#!/usr/bin/env bash
#
# Confirms `spec-guard.sh` actually fails on a deliberate violation, and passes
# on a clean tree. A guard nobody tested is indistinguishable from a guard that
# matches nothing, and both are green.
#
#   https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#notes-on-the-harder-criteria
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
#
# The violating fixture is GENERATED, never committed. A provider hostname or a
# key-shaped literal in a committed test fixture is itself the violation the
# guard exists to catch — "anywhere in the Talos codebase" — and exempting its
# path would need an allowlist entry, which is empty at MVP. So the fixture
# lives in a temporary directory for the length of this run.
#
# The literals below are the only violating strings in the repository, which is
# why `tools/spec-guard/` is the one directory the guard does not scan.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD="$SCRIPT_DIR/spec-guard.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

failed=0
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass() { printf '  ok    %s\n' "$1"; }
fail() {
    printf '  FAIL  %s\n' "$1"
    [ "$#" -gt 1 ] && printf '        %s\n' "$2"
    failed=1
}

# ── case 1: a tree with one deliberate violation per check ──────────────────
bad="$work/violating"
mkdir -p "$bad/Sources/TalosCore" "$bad/Sources/TalosAdapters" "$bad/Talos" "$bad/docs" \
    "$bad/Tests/TalosAdaptersTests" "$bad/Tests/TalosCoreTests"

# check 1 — a model provider hostname, and check 2 — a vendored SDK import.
cat >"$bad/Sources/TalosCore/ProviderClient.swift" <<'SWIFT'
import Anthropic
let endpoint = "https://api.anthropic.com/v1/messages"
let ollama = "http://localhost:11434/api/generate"
SWIFT

# check 2 — a model SDK dependency in a manifest.
cat >"$bad/Package.swift" <<'SWIFT'
.package(url: "https://github.com/example/openai-swift", from: "1.0.0")
SWIFT

# check 3 — a key-shaped literal and a key-handling pattern.
cat >"$bad/Talos/Secrets.swift" <<'SWIFT'
let key = "sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAAAAAA"
let fromEnv = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
SWIFT

# check 3 — a key-shaped literal in Markdown, which is scanned for keys only.
cat >"$bad/LEAK.md" <<'MD'
Paste your key: AKIAAAAAAAAAAAAAAAAA
MD

# check 4 — PTY allocation and a subprocess spawn outside the adapter layer.
cat >"$bad/Sources/TalosCore/Spawner.swift" <<'SWIFT'
let master = forkpty(nil, nil, nil, nil)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/bin/sh")
SWIFT

# NOT a violation — the adapter layer is the one place a spawn is permitted.
cat >"$bad/Sources/TalosAdapters/Launcher.swift" <<'SWIFT'
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
SWIFT

# NOT a violation — the adapter module's own test target, where "nothing
# survives" is asserted against a real process tree.
# https://github.com/CalixtoTheBugHunter/talos/issues/52
cat >"$bad/Tests/TalosAdaptersTests/RealProcessTests.swift" <<'SWIFT'
let process = AgentProcess(executablePath: "/bin/sh", arguments: ["-c", "sleep 300 & echo $!; wait"])
SWIFT

# check 4 — still a violation. The exemption above is one test target, not
# every test target, and this case is what stops it widening silently.
cat >"$bad/Tests/TalosCoreTests/SpawnerTests.swift" <<'SWIFT'
var pid: pid_t = 0
posix_spawn(&pid, "/bin/bash", nil, nil, nil, nil)
SWIFT

# NOT a violation — prose naming a hostname is not a client.
cat >"$bad/docs/note.md" <<'MD'
Talos never calls api.anthropic.com; the agent CLI does.
MD

out="$("$GUARD" "$bad" 2>&1)" && status=0 || status=$?

printf 'A deliberate violation fails the check\n'
if [ "$status" -ne 0 ]; then
    pass "exits non-zero (exit $status)"
else
    fail "exits non-zero" "the guard passed a tree with eight planted violations"
fi

expect_reported() { # expect_reported <check name>
    if printf '%s' "$out" | grep -qF "spec-guard: $1"; then
        pass "reports: $1"
    else
        fail "reports: $1" "no such check appeared in the output"
    fi
}

expect_reported 'model provider hostname'
expect_reported 'model SDK or MCP client dependency in a manifest'
expect_reported 'model SDK or MCP client import'
expect_reported 'API-key-shaped literal'
expect_reported 'model API key handling'
expect_reported 'PTY allocation outside the adapter layer'
expect_reported 'subprocess spawn outside the adapter layer'

expect_silent() { # expect_silent <path> <why it is legitimate>
    if printf '%s' "$out" | grep -qF "$1"; then
        fail "does not flag $1" "$2"
    else
        pass "does not flag $1 — $2"
    fi
}

expect_flagged() { # expect_flagged <path> <the rule it breaks>
    if printf '%s' "$out" | grep -qF "$1"; then
        pass "flags $1 — $2"
    else
        fail "flags $1" "$2"
    fi
}

# The exemption is one test target wide. Without this case, widening it to
# `Tests/` would still pass every assertion above.
expect_flagged 'Tests/TalosCoreTests/SpawnerTests.swift' \
    'only the adapter layer may spawn, and this is not it'

expect_silent 'Sources/TalosAdapters/Launcher.swift' 'the adapter layer may spawn'
expect_silent 'Tests/TalosAdaptersTests/RealProcessTests.swift' \
    "the adapter module's own tests assert that nothing survives a stop"
expect_silent 'docs/note.md' 'Markdown naming a hostname is prose, not a client'

# ── case 2: a clean tree passes ─────────────────────────────────────────────
# Without this case, a guard that failed on everything would satisfy case 1.
echo
printf 'A clean tree passes the check\n'
clean="$work/clean"
mkdir -p "$clean/Sources/TalosCore" "$clean/Sources/TalosAdapters"
cat >"$clean/Sources/TalosCore/Fine.swift" <<'SWIFT'
public enum Fine { public static let value = 1 }
SWIFT
cat >"$clean/Sources/TalosAdapters/Fine.swift" <<'SWIFT'
public enum AlsoFine { public static let value = 2 }
SWIFT

if clean_out="$("$GUARD" "$clean" 2>&1)"; then
    pass 'exits zero on a tree with no violations'
else
    fail 'exits zero on a tree with no violations' "$clean_out"
fi

# ── case 3: the adapter layer's exemption is asserted, not assumed ──────────
echo
printf 'A missing adapter layer fails the check\n'
vacuous="$work/vacuous"
mkdir -p "$vacuous/Sources/TalosCore"
cat >"$vacuous/Sources/TalosCore/Fine.swift" <<'SWIFT'
public enum Fine { public static let value = 1 }
SWIFT

vacuous_out="$("$GUARD" "$vacuous" 2>&1)" && vacuous_status=0 || vacuous_status=$?
if [ "$vacuous_status" -ne 0 ] && printf '%s' "$vacuous_out" | grep -qF 'the adapter layer does not exist'; then
    pass 'a Sources tree with no adapter layer is reported'
else
    fail 'a Sources tree with no adapter layer is reported' \
        'the spawn exemption would apply to a module that is not there'
fi

# ── case 4: the exclusion and the allowlist stay narrow ─────────────────────
echo
printf 'The exclusion and the allowlist stay narrow\n'

# The guard cannot scan its own pattern table, so this directory is excluded.
# That is only safe while nothing shippable hides in it.
swift_here="$(find "$REPO_ROOT/tools/spec-guard" -name '*.swift' -print 2>/dev/null || true)"
if [ -z "$swift_here" ]; then
    pass 'tools/spec-guard holds no Swift, so the exclusion hides no product code'
else
    fail 'tools/spec-guard holds no Swift' "$swift_here"
fi

# "The allowlist of legitimate exceptions is empty at MVP" —
# https://github.com/CalixtoTheBugHunter/talos/issues/24
if grep -qE '^ALLOWLIST=\(\)[[:space:]]*$' "$GUARD"; then
    pass 'the allowlist is empty at MVP'
else
    fail 'the allowlist is empty at MVP' \
        'an entry exists; it needs a `# SPEC: <wiki URL>` comment citing the decision'
fi

echo
if [ "$failed" -eq 0 ]; then
    echo 'spec-guard self-test: all cases pass.'
else
    echo 'spec-guard self-test: failed. The guard does not do what it claims.' >&2
fi
exit "$failed"
