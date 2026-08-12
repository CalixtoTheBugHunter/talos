#!/usr/bin/env bash
#
# Confirms `pr-title-guard.sh` actually fails on a deliberate violation, and
# passes on every title Conventional Commits allows. A guard nobody tested is
# indistinguishable from a guard that matches nothing, and both are green.
#
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#conventional-commits

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD="$SCRIPT_DIR/pr-title-guard.sh"

failed=0

pass() { printf '  ok    %s\n' "$1"; }
fail() {
    printf '  FAIL  %s\n' "$1"
    [ "$#" -gt 1 ] && printf '        %s\n' "$2"
    failed=1
}

expect_pass() { # expect_pass <label> <title> [body]
    local label="$1" title="$2" body="${3-}" out status=0
    out="$(PR_TITLE="$title" PR_BODY="$body" "$GUARD" 2>&1)" || status=$?
    if [ "$status" -eq 0 ]; then
        pass "$label"
    else
        fail "$label" "$out"
    fi
}

expect_fail() { # expect_fail <label> <title> [body]
    local label="$1" title="$2" body="${3-}" out status=0
    out="$(PR_TITLE="$title" PR_BODY="$body" "$GUARD" 2>&1)" || status=$?
    if [ "$status" -ne 0 ] && printf '%s' "$out" | grep -qF 'does not match Conventional Commits'; then
        pass "$label"
    else
        fail "$label" "$out"
    fi
}

printf '\nvalid titles — one per type\n'
expect_pass 'feat'     'feat(core): add never-allowlistable action registry'
expect_pass 'fix'      'fix(monitor): correct token parsing for resumed sessions'
expect_pass 'docs'     'docs(spec): document the message flow through the agent CLI'
expect_pass 'chore'    'chore(ci): bump the pinned SwiftLint version'
expect_pass 'perf'     'perf(monitor): reduce allocations in the session parser'
expect_pass 'refactor' 'refactor(ui): simplify the settings view hierarchy'
expect_pass 'test'     'test(adapter): add a fixture for a stopped process tree'
expect_pass 'build'    'build(security): sign the release DMG'
expect_pass 'ci'       'ci(a11y): add the accessibility gate workflow'

printf '\nvalid titles — one per scope\n'
expect_pass 'core'            'feat(core): add x'
expect_pass 'session'         'feat(session): add x'
expect_pass 'safeguards'      'feat(safeguards): add x'
expect_pass 'project-library' 'feat(project-library): add x'
expect_pass 'monitor'         'feat(monitor): add x'
expect_pass 'ui'              'feat(ui): add x'
expect_pass 'a11y'            'feat(a11y): add x'
expect_pass 'adapter'         'feat(adapter): add x'
expect_pass 'ci scope'        'feat(ci): add x'
expect_pass 'security'        'feat(security): add x'
expect_pass 'spec'            'feat(spec): add x'
expect_pass 'skills'          'feat(skills): add x'

printf '\nbreaking changes — accepted via `!` and via a footer\n'
expect_pass 'breaking via ! with no footer' 'feat(core)!: rename the session store'
expect_pass 'breaking via footer, no !' 'feat(core): rename the session store' \
    'Renames the store on disk.

BREAKING CHANGE: existing .talos/ directories must be migrated by hand.'
expect_pass 'breaking via both ! and footer' 'feat(core)!: rename the session store' \
    'BREAKING CHANGE: existing .talos/ directories must be migrated by hand.'

printf '\ninvalid titles\n'
expect_fail 'no type at all'          'Add a new feature'
expect_fail 'unknown type'            'feature(core): add x'
expect_fail 'missing scope'           'feat: add x'
expect_fail 'unknown scope'           'feat(nonsense): add x'
expect_fail 'missing colon'           'feat(core) add x'
expect_fail 'missing space after colon' 'feat(core):add x'
expect_fail 'empty subject'           'feat(core): '
expect_fail 'uppercase type'          'Feat(core): add x'
expect_fail 'empty title'             ''

printf '\n'
if [ "$failed" -eq 0 ]; then
    printf 'self-test: pr-title-guard passes every valid title, including both breaking-\n'
    printf '           change forms, and fails every invalid one with the SPEC cited.\n'
    exit 0
fi

printf '::error::self-test: pr-title-guard does not enforce what § Conventional Commits\n'
printf '  says it does.\n'
printf '  https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#conventional-commits\n'
exit 1
