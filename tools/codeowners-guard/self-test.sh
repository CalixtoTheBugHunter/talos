#!/usr/bin/env bash
#
# Confirms `codeowners-guard.sh` actually fails on a deliberate violation, and
# passes on a clean input. A guard nobody tested is indistinguishable from a
# guard that matches nothing, and both are green.
#
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#protection-rules-on-main
#
# Part 1 tests check 2 (the six SPEC categories) against generated CODEOWNERS
# fixtures in TREE MODE — no network, no push.
#
# Part 2 tests check 1 (the live GitHub parse-error check) by shadowing `gh` on
# PATH with a stub that returns a canned response. `codeowners-guard.sh` asks
# GitHub about a ref that must already exist there, so a fixture this script
# could push is not an option without granting CI write access it should not
# need — this proves the pass/fail LOGIC that consumes GitHub's answer,
# against the real, already-complete `.github/CODEOWNERS`, instead.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD="$SCRIPT_DIR/codeowners-guard.sh"

failed=0
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass() { printf '  ok    %s\n' "$1"; }
fail() {
    printf '  FAIL  %s\n' "$1"
    [ "$#" -gt 1 ] && printf '        %s\n' "$2"
    failed=1
}

# ── part 1: check 2 — the six SPEC categories, in tree mode ─────────────────
printf '\ncheck 2 — the six SPEC categories\n'

# The complete fixture: one line per category. Real, not fictional — this is
# the repository's own CODEOWNERS content, so the fixture cannot drift from
# what check 2's example paths were written to cover.
write_complete() { # write_complete <dir>
    mkdir -p "$1/.github"
    cat >"$1/.github/CODEOWNERS" <<'OWNERS'
/Sources/TalosSafeguards/   @CalixtoTheBugHunter
/Sources/TalosAdapters/     @CalixtoTheBugHunter
*Keychain*.swift            @CalixtoTheBugHunter
*Secret*.swift              @CalixtoTheBugHunter
/.github/workflows/         @CalixtoTheBugHunter
/.claude/skills/            @CalixtoTheBugHunter
/tools/spec-guard/          @CalixtoTheBugHunter
OWNERS
}

complete="$work/complete"
write_complete "$complete"
if "$GUARD" "$complete" >/dev/null 2>&1; then
    pass 'a complete CODEOWNERS passes'
else
    fail 'a complete CODEOWNERS passes' "$("$GUARD" "$complete" 2>&1)"
fi

# One case per category: the complete fixture with exactly that category's
# line removed. Each must be reported by name, and by the example path it
# left unowned — proving a renamed or deleted line is caught rather than
# silently unowned.
check_category() { # check_category <label> <drop pattern> <missing example>
    local label="$1" drop="$2" example="$3" dir out status=0
    dir="$work/missing-$(printf '%s' "$label" | tr -c 'a-zA-Z0-9' '-')"
    write_complete "$dir"
    grep -vF "$drop" "$complete/.github/CODEOWNERS" >"$dir/.github/CODEOWNERS"

    out="$("$GUARD" "$dir" 2>&1)" || status=$?
    if [ "$status" -eq 0 ]; then
        fail "$label — reported missing" 'the guard passed a fixture with that category removed'
    elif printf '%s' "$out" | grep -qF "covers $label" && printf '%s' "$out" | grep -qF "$example"; then
        pass "$label — reported missing, naming $example"
    else
        fail "$label — reported missing, naming $example" "$out"
    fi
}

check_category 'the Safeguards gate' '/Sources/TalosSafeguards/' 'Sources/TalosSafeguards/Example.swift'
check_category 'the layer that spawns processes' '/Sources/TalosAdapters/' 'Sources/TalosAdapters/Example.swift'
check_category 'secret handling' '*Keychain*.swift' 'ExampleKeychainStore.swift'
check_category 'the credentials a release holds' '/.github/workflows/' '.github/workflows/example.yml'
check_category 'the skills every agent contributes through' '/.claude/skills/' '.claude/skills/example-skill/SKILL.md'
check_category 'the spec-guard check that enforces DoD 11' '/tools/spec-guard/' 'tools/spec-guard/spec-guard.sh'

# A complete, correct CODEOWNERS must stay covered even when an unrelated file
# in the CALLER's cwd happens to collide with a bare filename glob. `covered()`
# parses each pattern with `read`, never `set -- $line` — the earlier version
# glob-expanded an unquoted `*Keychain*.swift` against real files in cwd and
# reported a fully correct file as missing that category.
collide_dir="$work/collide-caller-cwd"
mkdir -p "$collide_dir"
touch "$collide_dir/ZKeychainZ.swift"
if out="$(cd "$collide_dir" && "$GUARD" "$complete" 2>&1)"; then
    pass 'a colliding filename in the caller cwd does not break a correct file'
else
    fail 'a colliding filename in the caller cwd does not break a correct file' "$out"
fi

# A pattern with no owner covers nothing — "silently unowned" is exactly the
# case of a line that still matches but assigns no one.
unowned="$work/unowned"
write_complete "$unowned"
sed -i.bak 's#^/tools/spec-guard/.*#/tools/spec-guard/#' "$unowned/.github/CODEOWNERS"
rm -f "$unowned/.github/CODEOWNERS.bak"
if out="$("$GUARD" "$unowned" 2>&1)"; then
    fail 'a pattern with no owner is treated as unowned' "$out"
else
    if printf '%s' "$out" | grep -qF 'the spec-guard check that enforces DoD 11'; then
        pass 'a pattern with no owner is treated as unowned'
    else
        fail 'a pattern with no owner is treated as unowned' "$out"
    fi
fi

# ── part 2: check 1 — the live parse-error check, gh stubbed ────────────────
printf '\ncheck 1 — GitHub'"'"'s own parse-error and unresolvable-owner check\n'

mkdir -p "$work/bin"
cat >"$work/bin/gh" <<'SH'
#!/usr/bin/env bash
# self-test double for `gh` — returns FAKE_GH_JSON for `gh api ...codeowners/errors...`
json="${FAKE_GH_JSON-}"
[ -n "$json" ] || json='{"errors":[]}'
case "${1-}/${2-}" in
    api/*codeowners/errors*) printf '%s' "$json" ;;
    *) exit 1 ;;
esac
SH
chmod +x "$work/bin/gh"

run_guard_with_fake_gh() { # run_guard_with_fake_gh <json>
    FAKE_GH_JSON="$1" PATH="$work/bin:$PATH" "$GUARD"
}

out="$(run_guard_with_fake_gh '{"errors":[{"message":"owner @nope is not a collaborator","line":3,"path":".github/CODEOWNERS"}]}' 2>&1)" && status=0 || status=$?
if [ "$status" -ne 0 ] && printf '%s' "$out" | grep -qF 'parse error or an unresolvable owner'; then
    pass 'a non-empty errors array fails the build'
else
    fail 'a non-empty errors array fails the build' "$out"
fi

out="$(run_guard_with_fake_gh '{"errors":[]}' 2>&1)" && status=0 || status=$?
if [ "$status" -eq 0 ]; then
    pass 'an empty errors array passes'
else
    fail 'an empty errors array passes' "$out"
fi

# A missing `gh` must fail the build, not silently skip the live check. Built
# by dropping every PATH entry that holds a `gh` executable — never by
# shadowing `gh` with something that still resolves, which would test a
# different codepath.
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
    out="$(PATH="$no_gh_path" "$GUARD" 2>&1)" && status=0 || status=$?
    if [ "$status" -ne 0 ] && printf '%s' "$out" | grep -qF 'gh is required'; then
        pass 'gh missing fails the build rather than silently passing'
    else
        fail 'gh missing fails the build rather than silently passing' "$out"
    fi
fi

# ── verdict ─────────────────────────────────────────────────────────────────
printf '\n'
if [ "$failed" -eq 0 ]; then
    printf 'self-test: codeowners-guard fails on every missing category and on a\n'
    printf '           reported parse error, and passes on a complete, error-free input.\n'
    exit 0
fi

printf '::error::self-test: codeowners-guard does not enforce what § Protection rules on\n'
printf '  `main` says it does.\n'
printf '  https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#protection-rules-on-main\n'
exit 1
