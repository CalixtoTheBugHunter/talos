#!/usr/bin/env bash
#
# Confirms `dependency-justification-guard.sh` fails when a new dependency has
# no justification, passes when it does, passes on a routine version bump
# (Dependabot's normal job) with no PR body at all, and passes when nothing
# changed. A guard nobody tested is indistinguishable from one that matches
# nothing, and both are green.
#
#   https://github.com/CalixtoTheBugHunter/talos/issues/31
#
# Built in a throwaway git repository, never committed to this one — the
# guard diffs Package.swift and .github/workflows/*.yml between two real
# commits, so it needs a real history to walk, the same reason
# tools/secret-scan/self-test.sh builds one rather than using a plain tree.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD="$SCRIPT_DIR/dependency-justification-guard.sh"

failed=0
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass() { printf '  ok    %s\n' "$1"; }
fail() {
  printf '  FAIL  %s\n' "$1"
  [ "$#" -gt 1 ] && printf '        %s\n' "$2"
  failed=1
}

repo="$work/repo"
mkdir -p "$repo/.github/workflows"
git -C "$repo" init -q
git -C "$repo" config user.email 'self-test@example.invalid'
git -C "$repo" config user.name 'self-test'
git -C "$repo" config commit.gpgsign false

cat >"$repo/Package.swift" <<'EOF'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Fixture",
    dependencies: [],
    targets: [.target(name: "Fixture")]
)
EOF

cat >"$repo/.github/workflows/ci.yml" <<'EOF'
name: ci
on: pull_request
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa # v7.0.1
EOF

git -C "$repo" add -A
git -C "$repo" commit -q -m 'base: no external dependency, one pinned action'
base="$(git -C "$repo" rev-parse HEAD)"

# ── case 1: a version bump — no new identifier — passes with no PR body ────
git -C "$repo" checkout -q -b bump
sed -i.bak 's/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa # v7.0.1/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb # v7.0.2/' \
  "$repo/.github/workflows/ci.yml"
rm -f "$repo/.github/workflows/ci.yml.bak"
git -C "$repo" commit -q -am 'bump: same action, new pinned sha'
bump="$(git -C "$repo" rev-parse HEAD)"

echo 'A routine version bump passes with no PR body'
out="$(BASE_SHA="$base" HEAD_SHA="$bump" PR_BODY='' "$GUARD" "$base" "$bump" "$repo" 2>&1)" && status=0 || status=$?
if [ "$status" -eq 0 ]; then
  pass 'exits zero — the pinned action name did not change, only its sha'
else
  fail 'exits zero on a routine version bump' "$out"
fi

# ── case 2: a genuinely new dependency, no justification — fails ───────────
git -C "$repo" checkout -q "$base"
git -C "$repo" checkout -q -b new-dep
cat >"$repo/Package.swift" <<'EOF'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Fixture",
    dependencies: [
        .package(url: "https://github.com/example/widget.git", from: "1.0.0")
    ],
    targets: [.target(name: "Fixture")]
)
EOF
cat >>"$repo/.github/workflows/ci.yml" <<'EOF'
      - uses: some-org/some-new-action@cccccccccccccccccccccccccccccccccccccccc # v1.0.0
EOF
git -C "$repo" commit -q -am 'new: add a swift package and a github action'
newdep="$(git -C "$repo" rev-parse HEAD)"

echo
echo 'A new dependency with no PR-body justification fails'
out="$(BASE_SHA="$base" HEAD_SHA="$newdep" PR_BODY='' "$GUARD" "$base" "$newdep" "$repo" 2>&1)" && status=0 || status=$?
if [ "$status" -ne 0 ]; then
  pass "exits non-zero (exit $status)"
else
  fail 'exits non-zero' "the guard passed a new dependency with an empty PR body: $out"
fi
if printf '%s' "$out" | grep -q 'example/widget' && printf '%s' "$out" | grep -q 'some-org/some-new-action'; then
  pass 'names both the new swift package and the new github action'
else
  fail 'names both new identifiers' "$out"
fi

# ── case 3: the same new dependency, justified — passes ────────────────────
justified_body='## Dependency justification

- [ ] N/A — no new dependency added
- [x] New dependency added, justified below:

widget is needed for X, MIT licensed, no model SDK or MCP client.'

echo
echo 'The same new dependency, with the PR body box checked, passes'
out="$(BASE_SHA="$base" HEAD_SHA="$newdep" PR_BODY="$justified_body" "$GUARD" "$base" "$newdep" "$repo" 2>&1)" && status=0 || status=$?
if [ "$status" -eq 0 ]; then
  pass 'exits zero once the justification box is checked'
else
  fail 'exits zero once the justification box is checked' "$out"
fi

# ── case 4: base == head — nothing changed — passes ─────────────────────────
echo
echo 'No diff at all passes regardless of PR body'
out="$(BASE_SHA="$base" HEAD_SHA="$base" PR_BODY='' "$GUARD" "$base" "$base" "$repo" 2>&1)" && status=0 || status=$?
if [ "$status" -eq 0 ]; then
  pass 'exits zero when base and head are the same commit'
else
  fail 'exits zero when base and head are the same commit' "$out"
fi

echo
if [ "$failed" -eq 0 ]; then
  echo 'dependency-justification-guard self-test: all cases pass.'
else
  echo 'dependency-justification-guard self-test: failed. The guard does not do what it claims.' >&2
fi
exit "$failed"
