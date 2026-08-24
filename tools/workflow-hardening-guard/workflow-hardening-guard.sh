#!/usr/bin/env bash
#
# workflow-hardening-guard — asserts every workflow under .github/workflows/
# follows the six rules issue #32 built and § Workflow hardening states:
#
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#workflow-hardening
#   https://github.com/CalixtoTheBugHunter/talos/issues/32
#
# This is a STEP INSIDE the `lint` stage, not a stage of its own, so it adds
# no required status check on `main` — the same precedent `codeowners-guard`,
# `pr-title-guard`, and `dependency-justification-guard` set. Per decision 64:
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
#
# Usage:
#   tools/workflow-hardening-guard/workflow-hardening-guard.sh        # this repository
#   tools/workflow-hardening-guard/workflow-hardening-guard.sh <path> # <path>/.github/workflows only
#
# The second form is TREE MODE, for `self-test.sh`: a synthetic fixture tree
# that was never pushed, checked without touching the real repository.
#
# ── What this check does NOT claim ──────────────────────────────────────────
#
#   - Check 5 (fork-PR secrets) matches a bare `secrets.` reference against a
#     file whose `on:` block names `pull_request` without `_target`. It does
#     not trace which job or step a secret reference sits in against which
#     trigger gates that step with an `if:` — a workflow that is safe only
#     because of such an `if:` still reports as a violation here, and the fix
#     is to keep the secret out of a `pull_request`-triggered file entirely
#     rather than to gate it, which is what the rule asks for anyway.
#   - Check 6 (`pull_request_target` justification) looks for a comment
#     containing "justif" within a few lines of the trigger. It does not
#     grade whether the justification is actually sound — the same depth
#     `dependency-justification-guard` checks a justification box at.
#   - Neither check parses arbitrary YAML. Both work on this repository's own
#     workflow files, which declare `on:` as a small, flat block. A workflow
#     using YAML anchors, flow-style mappings, or a deeply nested `on:` is
#     outside what the line-oriented parsing below understands.

set -euo pipefail

SPEC='https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#workflow-hardening'

hits=0

report() { # report <check> <rule> <file> <evidence>
    hits=$((hits + 1))
    printf '::error::workflow-hardening-guard: %s\n' "$1"
    printf '  rule: %s\n' "$2"
    printf '  spec: %s\n' "$SPEC"
    printf '  file: %s\n' "$3"
    [ -z "${4-}" ] || printf '%s\n' "$4" | sed 's/^/  /'
    printf '\n'
}

# ── the scan surface ─────────────────────────────────────────────────────────
SCAN_ROOT="${1-}"
if [ -n "$SCAN_ROOT" ]; then
    [ -d "$SCAN_ROOT" ] || { printf 'workflow-hardening-guard: not a directory: %s\n' "$SCAN_ROOT" >&2; exit 2; }
    BASE="$(cd "$SCAN_ROOT" && pwd)"
else
    command -v git >/dev/null || { echo 'workflow-hardening-guard: git is required' >&2; exit 2; }
    BASE="$(git rev-parse --show-toplevel)"
fi

WORKFLOWS_DIR="$BASE/.github/workflows"
[ -d "$WORKFLOWS_DIR" ] || {
    printf '::error::workflow-hardening-guard: no %s\n' "$WORKFLOWS_DIR" >&2
    exit 2
}

files=()
while IFS= read -r f; do files+=("$f"); done < <(find "$WORKFLOWS_DIR" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)

if [ "${#files[@]}" -eq 0 ]; then
    printf '::error::workflow-hardening-guard: no workflow files found under %s\n' "$WORKFLOWS_DIR" >&2
    exit 2
fi

printf 'workflow-hardening-guard: checking %d workflow file(s) under %s\n\n' "${#files[@]}" "$WORKFLOWS_DIR"

# ── helpers ──────────────────────────────────────────────────────────────────

# top_level_block <file> <key> — the unindented `<key>:` line and every line
# under it up to (excluding) the next unindented, non-blank, non-comment line.
top_level_block() { # top_level_block <file> <key>
    awk -v key="^${2}:" '
        BEGIN { found = 0 }
        $0 ~ key { found = 1; print; next }
        found && /^[^[:space:]#]/ { exit }
        found { print }
    ' "$1"
}

# ── 1 & 2. top-level `permissions:`, explicit and no more than contents:read ─
check_permissions() { # check_permissions <file>
    local file="$1" block keys extra
    block="$(top_level_block "$file" 'permissions')"

    if [ -z "$block" ]; then
        report "no top-level permissions: in $(basename "$file")" \
            'Every workflow declares explicit permissions, defaulting to contents: read' \
            "$file" \
            'no unindented `permissions:` key found'
        return
    fi

    # Inline form: `permissions: read-all` or `permissions: {}` on one line.
    if printf '%s\n' "$block" | head -1 | grep -qE '^permissions:[[:space:]]*read-all[[:space:]]*$'; then
        report "top-level permissions: read-all in $(basename "$file")" \
            'Every workflow defaults to contents: read, not read-all' \
            "$file" \
            "$(printf '%s\n' "$block" | head -1)"
        return
    fi

    # Every indented `key: value` line under the block, excluding comments.
    keys="$(printf '%s\n' "$block" | tail -n +2 | grep -E '^[[:space:]]+[A-Za-z_-]+:' | sed -E 's/^[[:space:]]+([A-Za-z_-]+):[[:space:]]*([A-Za-z_-]+).*/\1: \2/' || true)"

    if [ -z "$keys" ]; then
        report "top-level permissions: block in $(basename "$file") grants nothing readable" \
            'Every workflow declares explicit permissions, defaulting to contents: read' \
            "$file" \
            "$block"
        return
    fi

    extra="$(printf '%s\n' "$keys" | grep -vFx 'contents: read' || true)"
    if [ -n "$extra" ]; then
        report "top-level permissions: in $(basename "$file") grants more than contents: read" \
            'Elevated permissions are granted per-job, never workflow-wide' \
            "$file" \
            "$extra"
    fi
}

# ── 3 & 4. every non-local action pinned to a full commit SHA + version note ─
check_pins() { # check_pins <file>
    local file="$1" line ref_and_comment action_at ref comment
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        # Only a `uses:` line naming a remote action (owner/repo[/path]@ref).
        # `./local-action` and `docker://` carry no publisher to compromise.
        action_at="$(printf '%s\n' "$line" | grep -oE 'uses:[[:space:]]*[^[:space:]]+@[^[:space:]]+')" || continue
        [ -n "$action_at" ] || continue
        case "$action_at" in *'uses: ./'*|*'uses: docker://'*) continue ;; esac

        ref_and_comment="${action_at#*@}"
        ref="${ref_and_comment%%[[:space:]]*}"
        comment="$(printf '%s\n' "$line" | grep -oE '#.*$' || true)"

        if ! printf '%s' "$ref" | grep -qE '^[0-9a-fA-F]{40}$'; then
            report "mutable ref in $(basename "$file"): $action_at" \
                'Every third-party action is pinned to a full commit SHA, not a tag' \
                "$file" \
                "$line"
            continue
        fi

        if ! printf '%s' "$comment" | grep -qE '^#[[:space:]]*\S+'; then
            report "pinned SHA with no version comment in $(basename "$file"): $action_at" \
                'A comment beside each pin records the human-readable version' \
                "$file" \
                "$line"
        fi
    done < <(grep -E '^\s*(-\s*)?uses:' "$file")
}

# ── 5. no secrets.* in a workflow triggered by a bare pull_request ──────────
check_fork_secrets() { # check_fork_secrets <file>
    local file="$1" on_block
    on_block="$(top_level_block "$file" 'on')"
    # Bare `return` (no code) would propagate the triggering command's exit
    # status as the FUNCTION's return status — fatal under `set -e` when this
    # function is later called as a bare statement, since "not a match" is a
    # legitimate outcome here, not a failure.
    [ -n "$on_block" ] || return 0

    printf '%s' "$on_block" | grep -qE '(^|[^_])pull_request([^_a-zA-Z]|$)' || return 0
    printf '%s' "$on_block" | grep -q 'pull_request_target' && return 0

    if grep -qE 'secrets\.' "$file"; then
        report "secrets.* referenced in a bare pull_request workflow: $(basename "$file")" \
            'Workflows triggered by fork PRs never receive secrets' \
            "$file" \
            "$(grep -nE 'secrets\.' "$file")"
    fi
}

# ── 6. pull_request_target only with a beside-it justification comment ─────
check_pull_request_target() { # check_pull_request_target <file>
    local file="$1" lineno start ctx
    # Process substitution, not a pipe: a piped `while read` runs in a
    # subshell, and `report`'s `hits` increment would not survive it.
    while IFS=: read -r lineno _; do
        [ -n "$lineno" ] || continue
        start=$((lineno - 3))
        [ "$start" -lt 1 ] && start=1
        ctx="$(sed -n "${start},$((lineno + 1))p" "$file")"
        if ! printf '%s' "$ctx" | grep -qiE '#.*justif'; then
            report "pull_request_target with no justification comment in $(basename "$file")" \
                'pull_request_target is not used, or its use is justified in a comment' \
                "$file" \
                "line $lineno"
        fi
    done < <(grep -n 'pull_request_target' "$file" || true)
}

for f in "${files[@]}"; do
    check_permissions "$f"
    check_pins "$f"
    check_fork_secrets "$f"
    check_pull_request_target "$f"
done

# ── verdict ──────────────────────────────────────────────────────────────────
if [ "$hits" -eq 0 ]; then
    printf 'workflow-hardening-guard: no violations across %d workflow file(s).\n' "${#files[@]}"
    exit 0
fi

printf '::error::workflow-hardening-guard: %d check(s) failed.\n' "$hits"
printf '  %s\n' "$SPEC"
exit 1
