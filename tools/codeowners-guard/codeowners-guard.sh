#!/usr/bin/env bash
#
# codeowners-guard — asserts that .github/CODEOWNERS still parses and still
# covers the paths § Protection rules on `main` says are load-bearing.
#
# The rule it enforces lives on the wiki and is not restated here; each check
# below carries the page and anchor that binds it, and prints them on failure:
#
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#protection-rules-on-main
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order
#
# Usage:
#   tools/codeowners-guard/codeowners-guard.sh          # check this repository's CODEOWNERS
#   tools/codeowners-guard/codeowners-guard.sh <path>   # check <path>/.github/CODEOWNERS only
#
# The second form is TREE MODE, for `self-test.sh`: it runs only check 2 below,
# because check 1 asks GitHub about a ref it must already have — a synthetic
# fixture that was never pushed has no such ref, so tree mode does not claim to
# cover it. `self-test.sh` proves check 1 a different way: it shadows `gh` on
# PATH and runs this script in its normal, no-argument mode against the real
# repository, so the request goes through the fake binary instead of the
# network.
#
# This is a STEP INSIDE the `lint` stage, not a stage of its own, so it adds no
# required status check on `main` — see
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order
#
# ── What this check does NOT claim ──────────────────────────────────────────
#
#   - Check 1 answers only what GitHub's own validator answers: a parse error
#     or an unresolvable owner. It says nothing about whether an *owner* is the
#     right owner — that is a review judgement, not a grep.
#   - Check 2 covers the SIX categories § Protection rules on `main` names for
#     code-owner review. It does not check decision 63's addendum — the files
#     that carry the list itself (`.github/CODEOWNERS`, `docs/github/`) — which
#     is a separate SPEC line this item's acceptance criteria deliberately
#     scope out.
#   - Check 2 understands two pattern shapes: a root-anchored directory
#     (`/dir/sub/`) and a bare filename glob (`*sub*.ext`). A CODEOWNERS
#     pattern written in some other shape (a non-anchored directory segment, a
#     character class, `**`) is not matched, and this guard would then report
#     the category it covers as missing — a false failure rather than a false
#     pass, and this file is where that gap is recorded rather than silently
#     patched around.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── SPEC references, printed on failure ─────────────────────────────────────
PROTECTION='https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#protection-rules-on-main'

# The repository the live check asks about, and the ref within it. Both are
# overridable so a fork or a local branch can point this at itself.
REPO="${TALOS_REPO:-CalixtoTheBugHunter/talos}"

hits=0

report() { # report <check> <rule> <spec url> <evidence>
    hits=$((hits + 1))
    printf '::error::codeowners-guard: %s\n' "$1"
    printf '  rule: %s\n' "$2"
    printf '  spec: %s\n' "$3"
    printf '%s\n\n' "$4" | sed 's/^/  /'
}

# ── the scan surface ────────────────────────────────────────────────────────
SCAN_ROOT="${1-}"
if [ -n "$SCAN_ROOT" ]; then
    [ -d "$SCAN_ROOT" ] || { printf 'codeowners-guard: not a directory: %s\n' "$SCAN_ROOT" >&2; exit 2; }
    BASE="$(cd "$SCAN_ROOT" && pwd)"
    MODE='tree'
else
    command -v git >/dev/null || { echo 'codeowners-guard: git is required' >&2; exit 2; }
    BASE="$(git rev-parse --show-toplevel)"
    MODE='repository'
fi

CODEOWNERS_FILE="$BASE/.github/CODEOWNERS"
[ -f "$CODEOWNERS_FILE" ] || {
    printf '::error::codeowners-guard: no CODEOWNERS file at %s\n' "$CODEOWNERS_FILE" >&2
    exit 2
}

printf 'codeowners-guard: %s mode, %s\n\n' "$MODE" "$CODEOWNERS_FILE"

# ── 1. GitHub's own parser: a parse error or an unresolvable owner ─────────
# "what earns a path a place on it is that a mistake there is unrecoverable
# rather than merely annoying" — § Protection rules on `main`. GitHub's own
# validator is the authority on what is unresolvable, so this asks GitHub
# rather than re-deriving the answer with a second parser that could drift.
check_live_parse_errors() { # check_live_parse_errors <repo> <ref>
    local repo="$1" ref="$2" out status=0 count

    command -v gh >/dev/null 2>&1 || {
        printf '::error::codeowners-guard: gh is required — https://cli.github.com\n' >&2
        return 2
    }
    command -v jq >/dev/null 2>&1 || {
        printf '::error::codeowners-guard: jq is required\n' >&2
        return 2
    }

    out="$(gh api "repos/$repo/codeowners/errors?ref=$ref" 2>&1)" || status=$?
    if [ "$status" -ne 0 ]; then
        report 'could not reach the GitHub CODEOWNERS validator' \
            'A step inside lint fails when .github/CODEOWNERS has a parse error or an unresolvable owner' \
            "$PROTECTION" \
            "gh api repos/$repo/codeowners/errors?ref=$ref failed:
$out"
        return 1
    fi

    count="$(printf '%s' "$out" | jq '.errors | length' 2>/dev/null || echo 'invalid')"
    if [ "$count" = 'invalid' ]; then
        report 'the validator returned no readable errors array' \
            'A step inside lint fails when .github/CODEOWNERS has a parse error or an unresolvable owner' \
            "$PROTECTION" \
            "$out"
        return 1
    fi
    if [ "$count" -gt 0 ]; then
        local detail
        detail="$(printf '%s' "$out" | jq -r \
            '.errors[] | "line \(.line // "?"): \(.message) (\(.path // ".github/CODEOWNERS"))"')"
        report ".github/CODEOWNERS has a parse error or an unresolvable owner at $ref" \
            'A mistake there is unrecoverable rather than merely annoying' \
            "$PROTECTION" \
            "$detail"
        return 1
    fi
    return 0
}

if [ "$MODE" = 'repository' ]; then
    REF="${CODEOWNERS_GUARD_REF:-${GITHUB_SHA:-$(git -C "$BASE" rev-parse HEAD)}}"
    check_live_parse_errors "$REPO" "$REF" || true
else
    printf 'codeowners-guard: tree mode — skipping the live GitHub parse-error check (needs a pushed ref)\n\n'
fi

# ── 2. The six SPEC categories stay covered ─────────────────────────────────
# "the Safeguards gate, the layer that spawns processes, secret handling, the
# credentials a release holds, the skills every agent contributes through, and
# the spec-guard check ... that enforces DoD 11" — § Protection rules on
# `main`. Each row is a label and the representative path(s) that category
# names; a category is covered only if EVERY one of its example paths matches
# some CODEOWNERS pattern that carries an owner.
CATEGORIES=(
    'the Safeguards gate|Sources/TalosSafeguards/Example.swift'
    'the layer that spawns processes|Sources/TalosAdapters/Example.swift'
    'secret handling|ExampleKeychainStore.swift ExampleSecretStore.swift'
    'the credentials a release holds|.github/workflows/example.yml'
    'the skills every agent contributes through|.claude/skills/example-skill/SKILL.md'
    'the spec-guard check that enforces DoD 11|tools/spec-guard/spec-guard.sh'
)

# match_pattern <codeowners pattern> <example path> — the two shapes this
# repository's CODEOWNERS actually uses. Not a general gitignore engine; see
# the header for what a third shape does to this check.
match_pattern() {
    local pattern="$1" example="$2" glob
    case "$pattern" in
        /*)
            glob="${pattern#/}"
            case "$pattern" in */) glob="${glob}*" ;; esac
            case "$example" in $glob) return 0 ;; esac
            ;;
        */*)
            # An unanchored pattern with a directory segment. Outside the two
            # understood shapes — see the header note on what this means.
            return 1
            ;;
        *)
            case "$(basename "$example")" in $pattern) return 0 ;; esac
            ;;
    esac
    return 1
}

# covered <example path> <codeowners file> — true if some line's pattern
# matches, and that line names at least one owner.
covered() {
    local example="$1" file="$2" pattern line
    while IFS= read -r line; do
        line="${line%$'\r'}"
        # shellcheck disable=SC2086,SC2206
        set -- $line
        [ "$#" -eq 0 ] && continue
        pattern="$1"
        case "$pattern" in '#'*) continue ;; esac
        shift
        [ "$#" -ge 1 ] || continue
        match_pattern "$pattern" "$example" && return 0
    done <"$file"
    return 1
}

for entry in "${CATEGORIES[@]}"; do
    label="${entry%%|*}"
    examples="${entry#*|}"
    missing=''
    for example in $examples; do
        covered "$example" "$CODEOWNERS_FILE" || missing="$missing $example"
    done
    if [ -n "$missing" ]; then
        report "no CODEOWNERS pattern with an owner covers $label" \
            'A renamed directory is caught rather than silently unowned' \
            "$PROTECTION" \
            "example path(s) not covered:$missing"
    fi
done

# ── verdict ─────────────────────────────────────────────────────────────────
if [ "$hits" -eq 0 ]; then
    printf 'codeowners-guard: no violations. %s covers every SPEC category.\n' "$CODEOWNERS_FILE"
    exit 0
fi

printf '::error::codeowners-guard: %d check(s) failed.\n' "$hits"
printf 'Code-owner review only protects a path that .github/CODEOWNERS still names correctly.\n'
printf '  %s\n' "$PROTECTION"
exit 1
