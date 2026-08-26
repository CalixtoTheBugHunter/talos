#!/usr/bin/env bash
#
# spec-guard — the grep that MVP Definition of Done item 11 says it is.
#
# The rules it enforces live on the wiki and are not restated here; each check
# below carries the page and anchor that binds it, and prints them on failure:
#
#   https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#notes-on-the-harder-criteria
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order
#
# Usage:
#   tools/spec-guard/spec-guard.sh          # scan this repository's tracked files
#   tools/spec-guard/spec-guard.sh <path>   # scan every file under <path>
#
# The second form exists for `self-test.sh`, which generates a deliberately
# violating tree outside the repository. Committing such a fixture is not an
# option: a provider hostname or a key-shaped literal in a test fixture is
# itself the violation, per
# https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#notes-on-the-harder-criteria
# ("anywhere in the Talos codebase").
#
# Repository mode scans *tracked* files, so `.build`, `DerivedData`, and
# untracked scratch are out of scope by construction rather than by exclusion
# list.
#
# ── What this check does NOT claim ──────────────────────────────────────────
#
# Stated because a green run is otherwise read as a claim it never made:
#
#   - It does not scan `tools/spec-guard/` — see "the one exclusion" below.
#   - It is not a generic secret scanner. It matches provider-shaped key
#     prefixes, not high-entropy strings; entropy scanning is GitHub secret
#     scanning's job, per
#     https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#process-decisions
#   - It does not grep for a general HTTP client (`URLSession` and friends).
#     That surface is red flag 5 in `.claude/skills/orchestration-boundary`,
#     and it is in no acceptance criterion of
#     https://github.com/CalixtoTheBugHunter/talos/issues/24 — so a green run
#     here says nothing about it.
#   - It does not check for PTY allocation *inside* the adapter module. The
#     criterion it implements is scoped outside it.
#   - It does not check for a subprocess spawn inside the adapter *layer*, which
#     is the module and its own test target. § Stop kills the tree is asserted
#     against a real process tree there, per
#     https://github.com/CalixtoTheBugHunter/talos/issues/52 — see
#     ADAPTER_TEST_PREFIX below. No other test target is exempt.
#   - Markdown is prose, so it is scanned for key-shaped literals and for
#     nothing else. A page that names a forbidden hostname in order to forbid
#     it is not a violation of the rule it states.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "$0")"

# The one exclusion, and why it is not an allowlist entry.
#
# A grep for `api.anthropic.com` necessarily contains that string, and so does
# the self-test that writes the fixture. The scanner therefore cannot scan its
# own pattern table. That is structural — not a judgement that some violation
# here is acceptable — which is why it is a fixed constant rather than a row in
# ALLOWLIST below. `self-test.sh` asserts it stays narrow: this directory holds
# no Swift.
GUARD_DIR="tools/spec-guard"

# Legitimate exceptions. Empty at MVP.
#
# Each entry is a path prefix skipped by every check. Adding one requires a
# `# SPEC: <wiki URL>` comment on the entry's own line citing the decision that
# permits it, and the check below fails the build when that comment is absent —
# so the requirement is enforced rather than documented.
ALLOWLIST=()

# ── SPEC references, printed on failure ─────────────────────────────────────
DOD='https://github.com/CalixtoTheBugHunter/talos/wiki/MVP-Definition-of-Done#checklist'
BOUNDARY='https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary'
CONSEQUENCES="$BOUNDARY#consequences-that-must-hold-at-all-times"
SPAWN="$BOUNDARY#only-the-adapter-layer-spawns-a-process"
CONSOLE='https://github.com/CalixtoTheBugHunter/talos/wiki/Session-Console'

# The one module permitted to spawn a subprocess. A layer, not a name, per
# § Only the adapter layer spawns a process — the module that implements it is
# fixed by https://github.com/CalixtoTheBugHunter/talos/issues/36.
ADAPTER_PREFIX='Sources/TalosAdapters/'

# That module's own test target, exempt from the spawn check alone. § Stop kills
# the tree states its guarantee as "nothing survives", and
# https://github.com/CalixtoTheBugHunter/talos/issues/52 is where it is asserted
# against a real process tree — an assertion that cannot be written without
# spawning one. Scanning this directory for spawns would forbid the test the
# SPEC requires, which makes the scan surface the bug rather than the test.
# Narrow on purpose: it exempts nothing else, and no other test target.
ADAPTER_TEST_PREFIX='Tests/TalosAdaptersTests/'

hits=0

report() { # report <check> <rule> <spec url> <evidence>
    hits=$((hits + 1))
    printf '::error::spec-guard: %s\n' "$1"
    printf '  rule:     %s\n' "$2"
    printf '  spec:     %s\n' "$3"
    printf '  DoD #11:  %s\n' "$DOD"
    printf '%s\n\n' "$4" | sed 's/^/  /'
}

scan() { # scan <flags> <check> <regex> <rule> <spec url> <file>...
    local flags="$1" check="$2" regex="$3" rule="$4" url="$5"
    shift 5
    [ "$#" -gt 0 ] || return 0

    local out status=0
    out="$(grep "$flags" -e "$regex" "$@")" || status=$?
    if [ "$status" -eq 0 ]; then
        report "$check" "$rule" "$url" "$out"
    elif [ "$status" -gt 1 ]; then
        printf '::error::spec-guard: grep exited %d while running "%s"\n' "$status" "$check"
        hits=$((hits + 1))
    fi
}

# ── the scan surface ────────────────────────────────────────────────────────
SCAN_ROOT="${1-}"
if [ -n "$SCAN_ROOT" ]; then
    [ -d "$SCAN_ROOT" ] || { printf 'spec-guard: not a directory: %s\n' "$SCAN_ROOT" >&2; exit 2; }
    BASE="$(cd "$SCAN_ROOT" && pwd)"
    MODE='tree'
else
    command -v git >/dev/null || { echo 'spec-guard: git is required' >&2; exit 2; }
    BASE="$(git rev-parse --show-toplevel)"
    MODE='repository'
fi
cd "$BASE"

list_files() {
    if [ "$MODE" = 'tree' ]; then
        find . -type f -print0
    else
        git ls-files -z
    fi
}

allowlisted() { # allowlisted <path>
    local entry
    for entry in ${ALLOWLIST[@]+"${ALLOWLIST[@]}"}; do
        case "$1" in "$entry"*) return 0 ;; esac
    done
    return 1
}

all_files=()
code_files=()
swift_outside_adapter=()
swift_outside_adapter_layer=()
swift_files=()
manifest_files=()

while IFS= read -r -d '' path; do
    path="${path#./}"
    case "$path" in "$GUARD_DIR"/*) continue ;; esac
    allowlisted "$path" && continue
    all_files+=("$path")

    # Prose is scanned for key-shaped literals only — see the header.
    case "$path" in *.md) ;; *) code_files+=("$path") ;; esac

    case "$path" in
        *.swift)
            swift_files+=("$path")
            case "$path" in
                "$ADAPTER_PREFIX"*) ;;
                *) swift_outside_adapter+=("$path") ;;
            esac
            case "$path" in
                "$ADAPTER_PREFIX"* | "$ADAPTER_TEST_PREFIX"*) ;;
                *) swift_outside_adapter_layer+=("$path") ;;
            esac
            ;;
    esac

    case "$path" in
        Package.swift | Package.resolved | *.pbxproj) manifest_files+=("$path") ;;
    esac
done < <(list_files)

printf 'spec-guard: %s mode, %d file(s), %d allowlist entr%s\n\n' \
    "$MODE" "${#all_files[@]}" "${#ALLOWLIST[@]}" \
    "$([ "${#ALLOWLIST[@]}" -eq 1 ] && printf 'y' || printf 'ies')"

# ── 1. Model provider hostnames ─────────────────────────────────────────────
# "Talos ships no API client for Anthropic, Google, Amazon Bedrock, OpenAI, or
# Ollama." — § Consequences that must hold at all times
scan -nHIE 'model provider hostname' \
    'api\.anthropic\.com|generativelanguage\.googleapis\.com|bedrock[A-Za-z0-9.-]*\.amazonaws\.com|api\.openai\.com|:11434' \
    'Talos ships no API client for Anthropic, Google, Amazon Bedrock, OpenAI, or Ollama' \
    "$CONSEQUENCES" \
    ${code_files[@]+"${code_files[@]}"}

# ── 2. Model SDK and MCP client dependencies ────────────────────────────────
# "Talos ships no MCP client of its own." — § Consequences that must hold at all
# times. Manifests first, then the import form a vendored client would take.
scan -nHIEi 'model SDK or MCP client dependency in a manifest' \
    'anthropic|openai|generative-?ai|generativelanguage|aws-sdk-swift|bedrock|ollama|modelcontextprotocol|mcp-swift|swift-sdk-mcp' \
    'Talos ships no model API client and no MCP client of its own' \
    "$CONSEQUENCES" \
    ${manifest_files[@]+"${manifest_files[@]}"}

scan -nHIE 'model SDK or MCP client import' \
    '^[[:space:]]*(@[A-Za-z]+[[:space:]]+)?import[[:space:]]+(Anthropic|OpenAI|GoogleGenerativeAI|GenerativeAI|AWSBedrock|Ollama|MCP|ModelContextProtocol)' \
    'Talos ships no model API client and no MCP client of its own' \
    "$CONSEQUENCES" \
    ${swift_files[@]+"${swift_files[@]}"}

# ── 3. API keys ─────────────────────────────────────────────────────────────
# "Talos holds no model API keys." — § Consequences that must hold at all times.
# Key-shaped literals are scanned everywhere including Markdown: a real key
# pasted into a page is a leaked key, not documentation.
scan -nHIE 'API-key-shaped literal' \
    'sk-ant-[A-Za-z0-9_-]{16,}|sk-[A-Za-z0-9]{32,}|AIza[0-9A-Za-z_-]{35}|AKIA[0-9A-Z]{16}' \
    'Talos holds no model API keys' \
    "$CONSEQUENCES" \
    ${all_files[@]+"${all_files[@]}"}

scan -nHIE 'model API key handling' \
    'ANTHROPIC_API_KEY|CLAUDE_API_KEY|OPENAI_API_KEY|GOOGLE_API_KEY|GEMINI_API_KEY|GOOGLE_APPLICATION_CREDENTIALS|AWS_SECRET_ACCESS_KEY|AWS_ACCESS_KEY_ID|OLLAMA_API_KEY' \
    'Talos holds no model API keys; agent CLIs use their own existing authentication' \
    "$CONSEQUENCES" \
    ${code_files[@]+"${code_files[@]}"}

# ── 4. PTY allocation and shell spawning outside the adapter layer ──────────
# "It is deliberately not a PTY. There is no embedded shell tab." — Session
# Console. A PTY shell is out of scope for v1.0 and bypasses the Safeguards
# gate.
scan -nHIE 'PTY allocation outside the adapter layer' \
    'forkpty|openpty|posix_openpt|login_tty|ptsname|grantpt|unlockpt|/dev/ptmx|/dev/pty' \
    'The session console is deliberately not a PTY; there is no embedded shell tab' \
    "$CONSOLE" \
    ${swift_outside_adapter[@]+"${swift_outside_adapter[@]}"}

# "Only the agent adapter layer may spawn a subprocess. No other part of Talos
# may. ... A spawn anywhere outside the adapter layer is a defect, whatever it
# is for." — § Only the adapter layer spawns a process
#
# Scanned over the layer rather than the module: the adapter module's own test
# target is where "nothing survives" is asserted against a real process tree,
# and that assertion has to spawn one. See ADAPTER_TEST_PREFIX above.
scan -nHIE 'subprocess spawn outside the adapter layer' \
    'NSTask|(^|[^A-Za-z0-9_])(Foundation\.)?Process\(|posix_spawn|execv[pe]?\(|execl[ep]?\(|popen\(|/bin/sh|/bin/bash|/usr/bin/env' \
    'Only the agent adapter layer may spawn a subprocess. No other part of Talos may' \
    "$SPAWN" \
    ${swift_outside_adapter_layer[@]+"${swift_outside_adapter_layer[@]}"}

# ── 5. The adapter layer is the *only* exemption, and it exists ─────────────
# The check above exempts one prefix. If that prefix named nothing, the
# exemption would be silently vacuous and the rule unasserted — so the positive
# half is asserted rather than assumed. Runs only where a `Sources/` tree
# exists, which is what makes this a Talos module layout rather than an
# arbitrary directory.
if [ -d Sources ]; then
    if [ ! -d "${ADAPTER_PREFIX%/}" ]; then
        report 'the adapter layer does not exist' \
            'Only the agent adapter layer may spawn a subprocess. No other part of Talos may' \
            "$SPAWN" \
            "expected the one module permitted to spawn: ${ADAPTER_PREFIX%/}"
    fi
fi

# ── 6. The allowlist cites a SPEC decision per entry ───────────────────────
if [ "${#ALLOWLIST[@]}" -gt 0 ]; then
    uncited="$(sed -n '/^ALLOWLIST=(/,/^)/p' "$SCRIPT_PATH" |
        grep -nE '^[[:space:]]*["'\'']' |
        grep -vE '# SPEC: https://github\.com/CalixtoTheBugHunter/talos/wiki/' || true)"
    if [ -n "$uncited" ]; then
        report 'allowlist entry cites no SPEC decision' \
            'A hard constraint is rejected rather than negotiated; an exception needs a recorded decision' \
            'https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log' \
            "$uncited"
    fi
fi

# ── verdict ─────────────────────────────────────────────────────────────────
if [ "$hits" -eq 0 ]; then
    printf 'spec-guard: no violations. DoD #11 holds across %d file(s).\n' "${#all_files[@]}"
    exit 0
fi

printf '::error::spec-guard: %d check(s) failed.\n' "$hits"
printf 'The orchestration boundary is a hard constraint, and MVP DoD #11 is how it is\n'
printf 'checked. If this fails, the architecture has drifted and the fix is not cosmetic:\n'
printf '  %s\n  %s\n' "$BOUNDARY" "$DOD"
exit 1
