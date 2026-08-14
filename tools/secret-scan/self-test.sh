#!/usr/bin/env bash
#
# Confirms `secret-scan.sh` actually fails on a deliberate violation in both
# modes, and passes on a clean tree. A guard nobody tested is indistinguishable
# from a guard that matches nothing, and both are green.
#
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#a-scanners-self-test-never-commits-its-fixture-whole
#   https://github.com/CalixtoTheBugHunter/talos/issues/29
#
# The violating fixture is generated into a throwaway git repository, never
# committed to this one. gitleaks needs a real git history (`detect`) and a
# real staged index (`protect-staged`) to scan, so — unlike spec-guard's plain
# filesystem tree — this self-test builds an actual repo per case.
#
# Per decision 66, the fixture credential is assembled from non-matching parts
# below and never appears as one contiguous literal in this file's own
# committed source — a scanner walks a PR's full history, not only its head,
# so a literal committed once and fixed later still reads as a leak forever.
# That is why .gitleaks.toml still needs no allowlist entry for the assembled
# VALUE, only for this file's path: see the comment on that allowlist entry.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCAN="$SCRIPT_DIR/secret-scan.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG="$REPO_ROOT/.gitleaks.toml"

failed=0
work="$(mktemp -d)"
hook_fixture="$REPO_ROOT/.secret-scan-hook-self-test-fixture.yaml"
cleanup() {
  rm -rf "$work"
  git -C "$REPO_ROOT" restore --staged -- "$hook_fixture" >/dev/null 2>&1 || true
  rm -f "$hook_fixture"
}
trap cleanup EXIT

pass() { printf '  ok    %s\n' "$1"; }
fail() {
  printf '  FAIL  %s\n' "$1"
  [ "$#" -gt 1 ] && printf '        %s\n' "$2"
  failed=1
}

new_repo() { # new_repo <dir>
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email 'self-test@example.invalid'
  git -C "$1" config user.name 'self-test'
  git -C "$1" config commit.gpgsign false
}

# A real match against gitleaks' *upstream* `aws-access-token` rule, not a
# homemade regex here — proving the committed config still enforces the
# default ruleset, per "without disabling real detection". Deliberately NOT
# AWS's own published docs example access key: gitleaks allowlists that
# specific literal by name as a known non-secret, so a self-test built on it
# would silently prove nothing. This one is a random value in the same shape
# (`AKIA` + 16 chars from [A-Z2-7]) with no such exemption.
#
# Built from non-contiguous parts rather than one literal, per decision 66 —
# https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
# — the same technique Tests/TalosCoreTests/LogRedactionTests.swift already
# uses for its own secret-shaped test literals. Two independent reasons this
# matters, not one: tools/spec-guard/spec-guard.sh's own `AKIA[0-9A-Z]{16}`
# check has no way to see this file is a fixture generator and not a real
# key, so a contiguous literal here fails spec-guard the same way it fails
# gitleaks — correctly. And per decision 66, a scanner walks a PR's full
# commit history, not only its head, so a contiguous literal committed once
# and fixed in a later commit still reads as a leak on every subsequent scan
# — this is exactly what happened on this file's own first commit. The
# fixture only needs to be contiguous once assembled in the *generated* file
# gitleaks scans, never in this script's own committed source.
akia_suffix=''
for c in W D U B E W I 4 U Z Q P P 7 Q X; do
  akia_suffix="${akia_suffix}${c}"
done
FIXTURE_SECRET="AKIA${akia_suffix}"

# ── case 1: `detect` fails on a violating commit, passes on a clean one ─────
det="$work/detect-repo"
new_repo "$det"

printf 'read me\n' >"$det/README.md"
git -C "$det" add README.md
git -C "$det" commit -q -m 'clean commit'

clean_out="$("$SCAN" detect --source "$det" -c "$CONFIG" 2>&1)" && clean_status=0 || clean_status=$?

printf 'A clean history passes `detect`\n'
if [ "$clean_status" -eq 0 ]; then
  pass 'exits zero on a clean repository'
else
  fail 'exits zero on a clean repository' "$clean_out"
fi

{
  printf 'aws_key = "%s"\n' "$FIXTURE_SECRET"
} >"$det/config.yaml"
git -C "$det" add config.yaml
git -C "$det" commit -q -m 'violating commit'

violating_out="$("$SCAN" detect --source "$det" -c "$CONFIG" 2>&1)" && violating_status=0 || violating_status=$?

echo
printf 'A deliberate fixture credential fails `detect`\n'
if [ "$violating_status" -ne 0 ]; then
  pass "exits non-zero (exit $violating_status)"
else
  fail 'exits non-zero' "the scan passed a commit carrying an AWS-key-shaped literal"
fi
if printf '%s' "$violating_out" | grep -qi 'aws'; then
  pass 'reports an AWS-access-token finding'
else
  fail 'reports an AWS-access-token finding' "$violating_out"
fi

# ── case 2: `protect-staged` fails on a staged violation, passes on none ────
stg="$work/staged-repo"
new_repo "$stg"
printf 'read me\n' >"$stg/README.md"
git -C "$stg" add README.md
git -C "$stg" commit -q -m 'clean commit'

echo
printf 'Nothing staged passes `protect-staged`\n'
none_out="$("$SCAN" protect-staged --source "$stg" -c "$CONFIG" 2>&1)" && none_status=0 || none_status=$?
if [ "$none_status" -eq 0 ]; then
  pass 'exits zero with nothing staged'
else
  fail 'exits zero with nothing staged' "$none_out"
fi

printf 'aws_key = "%s"\n' "$FIXTURE_SECRET" >"$stg/staged-secret.yaml"
git -C "$stg" add staged-secret.yaml

echo
printf 'A deliberate fixture credential staged but uncommitted fails `protect-staged`\n'
staged_out="$("$SCAN" protect-staged --source "$stg" -c "$CONFIG" 2>&1)" && staged_status=0 || staged_status=$?
if [ "$staged_status" -ne 0 ]; then
  pass "exits non-zero (exit $staged_status)"
else
  fail 'exits non-zero' "the scan passed a staged AWS-key-shaped literal"
fi
if printf '%s' "$staged_out" | grep -qi 'aws'; then
  pass 'reports an AWS-access-token finding'
else
  fail 'reports an AWS-access-token finding' "$staged_out"
fi

# ── case 3: the allowlist exclusion stays narrow ─────────────────────────────
# Mirrors tools/spec-guard/self-test.sh's own "exclusion stays narrow" case:
# the only path excluded from the real scan is this fixture generator, and
# nothing else in this directory needs the exemption.
#
# Counts the entries INSIDE the `paths = [ ... ]` array, not occurrences of one
# specific string in the whole file — a substring count stays 1 even after a
# second, much broader entry (say, a catch-all `'''.*'''`) is added anywhere
# else in that array, which would silently exempt the entire repository from
# every gitleaks rule with this check still green.
echo
printf 'The allowlist exclusion stays narrow\n'
allowlist_entries="$(awk '
  /paths[[:space:]]*=[[:space:]]*\[/ { inside = 1; next }
  inside && /^\]/ { inside = 0 }
  inside && NF { count++ }
  END { print count + 0 }
' "$CONFIG")"
if [ "$allowlist_entries" -eq 1 ] && grep -qF '''tools/secret-scan/self-test\.sh''' "$CONFIG"; then
  pass 'the allowlist array has exactly one entry, and it is self-test.sh'
else
  fail 'the allowlist array has exactly one entry, and it is self-test.sh' \
    "found $allowlist_entries entr$([ "$allowlist_entries" = 1 ] && echo y || echo ies) — check .gitleaks.toml's [allowlist].paths"
fi

# --no-git scans the working tree directly rather than git history, so this
# holds even before these files are committed. It uses the real repo config,
# so self-test.sh's own fixture is already allowlisted and silent here — a hit
# on anything else in the directory is the one this case exists to catch.
others_out="$("$SCAN" detect --source "$REPO_ROOT/tools/secret-scan" -c "$CONFIG" --no-git 2>&1)" && others_status=0 || others_status=$?
if [ "$others_status" -eq 0 ]; then
  pass 'secret-scan.sh and README.md carry no secret-shaped literal, so only self-test.sh needs the exclusion'
else
  fail 'secret-scan.sh and README.md carry no secret-shaped literal' "$others_out"
fi

# ── case 4: .githooks/pre-commit itself fails on a staged fixture ───────────
# Cases 1-2 test the command the hook calls; this tests the hook script
# itself, so a future break in its own wiring — the wrong order, a typo in the
# `require` call, a line dropped during an edit — fails this instead of only
# showing up the next time someone commits a real secret. It runs against
# this real checkout rather than a throwaway repo, because the hook also runs
# design-guard unconditionally and design-guard has no meaning outside one —
# safe here because every other required CI check already establishes this
# tree is clean.
echo
printf 'The hook itself — not just secret-scan.sh — fails on a staged fixture\n'

printf 'aws_key = "%s"\n' "$FIXTURE_SECRET" >"$hook_fixture"
git -C "$REPO_ROOT" add "$hook_fixture"
hook_out="$(cd "$REPO_ROOT" && .githooks/pre-commit 2>&1)" && hook_status=0 || hook_status=$?
git -C "$REPO_ROOT" restore --staged -- "$hook_fixture" >/dev/null 2>&1 || true
rm -f "$hook_fixture"

if [ "$hook_status" -ne 0 ] && printf '%s' "$hook_out" | grep -qF 'secret-scan found a secret-shaped literal'; then
  pass 'the hook fails via its own secret-scan wiring, not a coincidental design-guard failure'
else
  fail 'the hook fails via its own secret-scan wiring' "$hook_out"
fi

echo
if [ "$failed" -eq 0 ]; then
  echo 'secret-scan self-test: all cases pass.'
else
  echo 'secret-scan self-test: failed. The guard does not do what it claims.' >&2
fi
exit "$failed"
