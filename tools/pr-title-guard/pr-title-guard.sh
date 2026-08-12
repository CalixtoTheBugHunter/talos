#!/usr/bin/env bash
#
# pr-title-guard — asserts a PR title follows Conventional Commits, per
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#conventional-commits
#
# Squash-merge makes the PR title the commit message, and CHANGELOG.md is
# generated from that message — an unvalidated title is a broken release
# note. This is a STEP INSIDE the `lint` stage, not a stage of its own, so it
# adds no required status check on `main` — the same precedent
# `design-guard` and `codeowners-guard` set, see
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order
#
# Usage:
#   tools/pr-title-guard/pr-title-guard.sh <title> [body]
#   PR_TITLE=<title> PR_BODY=<body> tools/pr-title-guard/pr-title-guard.sh
#
# PR_TITLE/PR_BODY take priority over the positional arguments, so CI can set
# them from ${{ github.event.pull_request.title }} / .body without the title
# ever crossing a shell word-splitting boundary.
#
# ── What this does NOT claim ────────────────────────────────────────────────
#
#   - It validates the TITLE's grammar only. A `BREAKING CHANGE:` footer lives
#     in the PR body, not the title, so this recognizes one when present
#     (reported, never rejected) without validating the footer's own prose.
#   - It does not enforce a subject length or a case convention beyond what
#     the SPEC states — the SPEC states none.

set -euo pipefail

SPEC='https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#conventional-commits'

TITLE="${PR_TITLE:-${1-}}"
BODY="${PR_BODY:-${2-}}"

TYPES='feat fix docs chore perf refactor test build ci'
SCOPES='core session safeguards project-library monitor ui a11y adapter ci security spec skills'

type_pattern="$(printf '%s' "$TYPES" | tr ' ' '|')"
scope_pattern="$(printf '%s' "$SCOPES" | tr ' ' '|')"

report_failure() { # report_failure <title>
    local title="$1"
    printf '::error::pr-title-guard: PR title does not match Conventional Commits.\n'
    printf '  title:    "%s"\n' "$title"
    printf '  expected: <type>(<scope>): <subject>\n'
    printf '  types:    %s\n' "$TYPES"
    printf '  scopes:   %s\n' "$SCOPES"
    printf '  example:  feat(safeguards): add never-allowlistable action registry\n'
    printf '  breaking: feat(core)!: rename the session store, or a BREAKING CHANGE: footer\n'
    printf '  spec:     %s\n' "$SPEC"
}

if [ -z "$TITLE" ]; then
    report_failure "$TITLE"
    exit 1
fi

if [[ "$TITLE" =~ ^(${type_pattern})\((${scope_pattern})\)!?:\ .+$ ]]; then
    printf 'pr-title-guard: "%s" matches Conventional Commits.\n' "$TITLE"

    if [[ "$TITLE" == *"!:"* ]]; then
        printf 'pr-title-guard: breaking change marked via `!`.\n'
    fi
    if printf '%s' "$BODY" | grep -qE '^BREAKING CHANGE: .+'; then
        printf 'pr-title-guard: breaking change marked via a `BREAKING CHANGE:` footer.\n'
    fi

    exit 0
fi

report_failure "$TITLE"
exit 1
