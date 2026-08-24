#!/usr/bin/env bash
#
# Confirms `workflow-hardening-guard.sh` actually fails on a deliberate
# violation of each of the six rules, and passes on a clean workflow. A guard
# nobody tested is indistinguishable from a guard that matches nothing, and
# both are green.
#
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#workflow-hardening
#
# Every case runs in TREE MODE against a synthetic fixture — no network, no
# push, and no dependency on this repository's own workflow files staying
# exactly as they are today.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD="$SCRIPT_DIR/workflow-hardening-guard.sh"

failed=0
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass() { printf '  ok    %s\n' "$1"; }
fail() {
    printf '  FAIL  %s\n' "$1"
    [ "$#" -gt 1 ] && printf '        %s\n' "$2"
    failed=1
}

# fixture <dir> <workflow.yml content> — a tree with exactly one workflow file.
fixture() { # fixture <dir> <content>
    mkdir -p "$1/.github/workflows"
    printf '%s\n' "$2" >"$1/.github/workflows/example.yml"
}

expect_pass() { # expect_pass <label> <content>
    local label="$1" dir out status=0
    dir="$work/pass-$(printf '%s' "$label" | tr -c 'a-zA-Z0-9' '-')"
    fixture "$dir" "$2"
    out="$("$GUARD" "$dir" 2>&1)" || status=$?
    if [ "$status" -eq 0 ]; then
        pass "$label"
    else
        fail "$label" "$out"
    fi
}

expect_fail() { # expect_fail <label> <content> <must contain in output>
    local label="$1" dir out status=0
    dir="$work/fail-$(printf '%s' "$label" | tr -c 'a-zA-Z0-9' '-')"
    fixture "$dir" "$2"
    out="$("$GUARD" "$dir" 2>&1)" || status=$?
    if [ "$status" -ne 0 ] && printf '%s' "$out" | grep -qF "$3"; then
        pass "$label"
    else
        fail "$label" "$out"
    fi
}

CLEAN='name: example

on:
  pull_request:

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1'

printf '\nthe clean case\n'
expect_pass 'a complete, hardened workflow passes' "$CLEAN"

printf '\ncheck 1 — explicit top-level permissions, defaulting to contents: read\n'
expect_fail 'no top-level permissions at all' \
'name: example

on:
  pull_request:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1' \
    'no top-level permissions'

expect_fail 'permissions: read-all at the top level' \
'name: example

on:
  pull_request:

permissions: read-all

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1' \
    'read-all'

printf '\ncheck 2 — elevated permissions are per-job, never workflow-wide\n'
expect_fail 'workflow-wide write permission' \
'name: example

on:
  pull_request:

permissions:
  contents: read
  pull-requests: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1' \
    'grants more than contents: read'

expect_pass 'the same elevation scoped to the job instead passes' \
'name: example

on:
  pull_request:

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1'

printf '\ncheck 3 — every third-party action pinned to a full commit SHA\n'
expect_fail 'a mutable tag instead of a SHA' \
'name: example

on:
  pull_request:

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7' \
    'mutable ref'

expect_pass 'a local action is exempt from the pin check' \
'name: example

on:
  pull_request:

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: ./.github/actions/local-thing'

printf '\ncheck 4 — a version comment beside each pin\n'
expect_fail 'a SHA pin with no version comment' \
'name: example

on:
  pull_request:

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1' \
    'no version comment'

printf '\ncheck 5 — workflows triggered by fork PRs never receive secrets\n'
expect_fail 'secrets referenced under a bare pull_request trigger' \
'name: example

on:
  pull_request:

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - run: echo "${{ secrets.SOME_TOKEN }}"' \
    'fork PRs never receive secrets'

expect_pass 'secrets under push (not a PR trigger) is not this rule'"'"'s case' \
'name: example

on:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - run: echo "${{ secrets.SOME_TOKEN }}"'

printf '\ncheck 6 — pull_request_target is unused, or justified in a comment\n'
expect_fail 'pull_request_target with no justification comment' \
'name: example

on:
  pull_request_target:

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1' \
    'no justification comment'

expect_pass 'pull_request_target with a justification comment passes' \
'name: example

# Justified: this workflow only labels an issue and never checks out fork content.
on:
  pull_request_target:

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1'

# ── this repository's own workflows must already be clean ──────────────────
printf '\nthis repository'"'"'s real workflows\n'
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
if out="$("$GUARD" "$REPO_ROOT" 2>&1)"; then
    pass 'this repository'"'"'s own .github/workflows/ passes'
else
    fail 'this repository'"'"'s own .github/workflows/ passes' "$out"
fi

# ── verdict ─────────────────────────────────────────────────────────────────
printf '\n'
if [ "$failed" -eq 0 ]; then
    printf 'self-test: workflow-hardening-guard fails on every deliberate violation of the\n'
    printf '           six rules, and passes on a clean workflow. %s\n' "$REPO_ROOT/.github/workflows"
    exit 0
fi

printf '::error::self-test: workflow-hardening-guard does not enforce what § Workflow\n'
printf '  hardening says it does.\n'
printf '  https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#workflow-hardening\n'
exit 1
