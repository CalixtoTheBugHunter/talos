#!/usr/bin/env bash
#
# Confirms `dependency-age-guard.sh` fails on a bump to a deliberately fresh
# version, passes on a bump to a deliberately old one, passes when nothing
# changed, treats a brand-new pin the same as a bump, passes on an unrelated
# edit that changes no pin's value, and fails rather than silently skips when
# `gh` is missing. A guard nobody tested is indistinguishable from one that
# matches nothing, and both are green.
#
#   https://github.com/CalixtoTheBugHunter/talos/issues/178
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#dependency-update-age
#
# Built in a throwaway git repository, never committed to this one — the guard
# diffs .github/workflows/*.yml and Package.swift between two real commits,
# the same reason tools/dependency-justification-guard/self-test.sh builds one
# rather than using a plain tree.
#
# `gh` is shadowed on PATH with a stub returning a canned commit date, the
# same technique tools/codeowners-guard/self-test.sh uses for its live check —
# a real lookup would require a real, aged tag this fixture cannot control.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD="$SCRIPT_DIR/dependency-age-guard.sh"

failed=0
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass() { printf '  ok    %s\n' "$1"; }
fail() {
    printf '  FAIL  %s\n' "$1"
    [ "$#" -gt 1 ] && printf '        %s\n' "$2"
    failed=1
}

# ── the fake `gh` — every call this guard makes is `gh api repos/.../commits/<ref> --jq ...`.
# FAKE_COMMIT_DATE controls the answer; unset makes the stub fail the call, so
# a test that forgets to set it fails loudly rather than passing by accident.
mkdir -p "$work/bin"
cat >"$work/bin/gh" <<'SH'
#!/usr/bin/env bash
if [ "${1-}" = 'api' ]; then
    if [ -z "${FAKE_COMMIT_DATE-}" ]; then
        echo 'self-test double: FAKE_COMMIT_DATE not set' >&2
        exit 1
    fi
    printf '%s\n' "$FAKE_COMMIT_DATE"
    exit 0
fi
exit 1
SH
chmod +x "$work/bin/gh"

# ── the fixture repository ──────────────────────────────────────────────────
repo="$work/repo"
mkdir -p "$repo/.github/workflows"
git -C "$repo" init -q
git -C "$repo" config user.email 'self-test@example.invalid'
git -C "$repo" config user.name 'self-test'
git -C "$repo" config commit.gpgsign false

cat >"$repo/.github/workflows/ci.yml" <<'EOF'
name: ci
on: pull_request
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa # v7.0.1
EOF

cat >"$repo/Package.swift" <<'EOF'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Fixture",
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2")
    ],
    targets: [.target(name: "Fixture")]
)
EOF

git -C "$repo" add -A
git -C "$repo" commit -q -m 'base'
base="$(git -C "$repo" rev-parse HEAD)"

run_guard() { # run_guard <base> <head> <min-age-hours> <fake-commit-date>
    PATH="$work/bin:$PATH" FAKE_COMMIT_DATE="$4" \
        BASE_SHA="$1" HEAD_SHA="$2" MIN_AGE_HOURS="$3" "$GUARD" "$1" "$2" "$repo" 2>&1
}

# ── case 1: nothing changed — passes, and never calls the fake gh ──────────
echo 'No diff at all passes with no gh call'
out="$(PATH="$work/bin:$PATH" BASE_SHA="$base" HEAD_SHA="$base" MIN_AGE_HOURS=24 "$GUARD" "$base" "$base" "$repo" 2>&1)" && status=0 || status=$?
if [ "$status" -eq 0 ]; then
    pass 'exits zero when base and head are the same commit'
else
    fail 'exits zero when base and head are the same commit' "$out"
fi

# ── case 2: an Action pin bumped to a FRESH commit — fails ─────────────────
git -C "$repo" checkout -q -b bump-action-fresh
sed -i.bak 's/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa # v7.0.1/2222222222222222222222222222222222222222 # v7.0.2/' \
    "$repo/.github/workflows/ci.yml"
rm -f "$repo/.github/workflows/ci.yml.bak"
git -C "$repo" commit -q -am 'bump: action to a new sha'
bump_action_fresh="$(git -C "$repo" rev-parse HEAD)"

echo
echo 'A GitHub Action bumped to a version published 1 hour ago fails'
one_hour_ago="$(date -u -v-1H +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '1 hour ago' +'%Y-%m-%dT%H:%M:%SZ')"
out="$(run_guard "$base" "$bump_action_fresh" 24 "$one_hour_ago")" && status=0 || status=$?
if [ "$status" -ne 0 ]; then
    pass "exits non-zero (exit $status)"
else
    fail 'exits non-zero on a fresh action bump' "$out"
fi
if printf '%s' "$out" | grep -q 'github action actions/checkout'; then
    pass 'names the fresh github action'
else
    fail 'names the fresh github action' "$out"
fi

# ── case 3: the same Action pin, but published well before the threshold ───
git -C "$repo" checkout -q "$base"
git -C "$repo" checkout -q -b bump-action-old
sed -i.bak 's/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa # v7.0.1/3333333333333333333333333333333333333333 # v7.0.3/' \
    "$repo/.github/workflows/ci.yml"
rm -f "$repo/.github/workflows/ci.yml.bak"
git -C "$repo" commit -q -am 'bump: action to a new sha, old version'
bump_action_old="$(git -C "$repo" rev-parse HEAD)"

echo
echo 'The same bump, published 1000 hours ago, passes'
old_date="$(date -u -v-1000H +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '1000 hours ago' +'%Y-%m-%dT%H:%M:%SZ')"
out="$(run_guard "$base" "$bump_action_old" 24 "$old_date")" && status=0 || status=$?
if [ "$status" -eq 0 ]; then
    pass 'exits zero once the pinned commit has aged past the threshold'
else
    fail 'exits zero once the pinned commit has aged past the threshold' "$out"
fi

# ── case 4: a Swift package requirement bumped to a FRESH version — fails ──
git -C "$repo" checkout -q "$base"
git -C "$repo" checkout -q -b bump-swift-fresh
cat >"$repo/Package.swift" <<'EOF'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Fixture",
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.3.0")
    ],
    targets: [.target(name: "Fixture")]
)
EOF
git -C "$repo" commit -q -am 'bump: yams requirement to a new version'
bump_swift_fresh="$(git -C "$repo" rev-parse HEAD)"

echo
echo 'A Swift package requirement bumped to a version published 1 hour ago fails'
out="$(run_guard "$base" "$bump_swift_fresh" 24 "$one_hour_ago")" && status=0 || status=$?
if [ "$status" -ne 0 ] && printf '%s' "$out" | grep -q 'swift package.*jpsim/Yams.*6\.3\.0'; then
    pass 'exits non-zero and names the fresh swift package requirement'
else
    fail 'exits non-zero and names the fresh swift package requirement' "$out"
fi

# ── case 5: a BRAND-NEW action pin (absent at base) — checked like a bump ──
git -C "$repo" checkout -q "$base"
git -C "$repo" checkout -q -b new-action
cat >>"$repo/.github/workflows/ci.yml" <<'EOF'
      - uses: some-org/some-new-action@5555555555555555555555555555555555555555 # v1.0.0
EOF
git -C "$repo" commit -q -am 'add: a brand-new pinned action'
new_action="$(git -C "$repo" rev-parse HEAD)"

echo
echo 'A brand-new action pin published 1 hour ago fails, the same as a bump'
out="$(run_guard "$base" "$new_action" 24 "$one_hour_ago")" && status=0 || status=$?
if [ "$status" -ne 0 ] && printf '%s' "$out" | grep -q 'github action some-org/some-new-action'; then
    pass 'exits non-zero and names the brand-new action'
else
    fail 'exits non-zero and names the brand-new action' "$out"
fi

# ── case 6: an unrelated edit that leaves every pin's value unchanged ──────
git -C "$repo" checkout -q "$base"
git -C "$repo" checkout -q -b unrelated-edit
cat >>"$repo/.github/workflows/ci.yml" <<'EOF'
      - run: echo "an unrelated step, no new uses: line"
EOF
git -C "$repo" commit -q -am 'unrelated: add a step that pins nothing'
unrelated="$(git -C "$repo" rev-parse HEAD)"

echo
echo 'An unrelated file edit that changes no pin value passes with no gh call'
out="$(PATH="$work/bin:$PATH" BASE_SHA="$base" HEAD_SHA="$unrelated" MIN_AGE_HOURS=24 "$GUARD" "$base" "$unrelated" "$repo" 2>&1)" && status=0 || status=$?
if [ "$status" -eq 0 ]; then
    pass 'exits zero — the existing pin is unchanged, the new line pins nothing'
else
    fail 'exits zero on an unrelated edit' "$out"
fi

# ── case 7: gh missing from PATH fails the build, not a silent pass ────────
echo
echo 'A missing gh fails the build rather than silently passing'
no_gh_path=''
still_has_git=0
while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    if [ -x "$dir/gh" ]; then continue; fi
    no_gh_path="$no_gh_path:$dir"
    [ -x "$dir/git" ] && still_has_git=1
done <<<"$(printf '%s' "$PATH" | tr ':' '\n')"
no_gh_path="${no_gh_path#:}"

if [ "$still_has_git" -ne 1 ]; then
    fail 'gh missing fails the build rather than silently passing' \
        'every PATH entry with gh also lacked git on this machine — cannot isolate the case'
else
    out="$(PATH="$no_gh_path" BASE_SHA="$base" HEAD_SHA="$bump_action_fresh" MIN_AGE_HOURS=24 "$GUARD" "$base" "$bump_action_fresh" "$repo" 2>&1)" && status=0 || status=$?
    if [ "$status" -ne 0 ] && printf '%s' "$out" | grep -qF 'gh is required'; then
        pass 'gh missing fails the build rather than silently passing'
    else
        fail 'gh missing fails the build rather than silently passing' "$out"
    fi
fi

# ── verdict ──────────────────────────────────────────────────────────────────
echo
if [ "$failed" -eq 0 ]; then
    echo 'dependency-age-guard self-test: all cases pass.'
else
    echo 'dependency-age-guard self-test: failed. The guard does not do what it claims.' >&2
fi
exit "$failed"
