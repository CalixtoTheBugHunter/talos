#!/usr/bin/env bash
#
# Confirms the no-values rule actually fails on a deliberate violation, and
# passes on the legitimate spelling. A guard nobody tested is indistinguishable
# from a guard that matches nothing, and both are green.
#
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Design-System#the-platform-is-the-design-system
#
# It covers BOTH halves of decision 56, because the split between them is an
# implementation detail a reader should not have to know to trust the rule:
#
#   - the six classes `.swiftlint.yml` owns, run through the repository's own
#     config rather than a copy of it, so the rules under test are the shipped
#     ones;
#   - the two classes `design-guard.sh` owns.
#
# The violating fixture is GENERATED, never committed. A hex literal or a
# `.colorset` in a committed test fixture is itself the violation the rule exists
# to catch, and there is no allowlist to exempt its path. So the fixture lives in
# a temporary directory for the length of this run.
#
# The literals below are the only violating strings in the repository, which is
# why `tools/design-guard/` is the one directory `design-guard.sh` does not scan.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD="$SCRIPT_DIR/design-guard.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# The same binary CI uses, then a developer's own. Absent, this is a failure
# rather than a skip: a skipped test is indistinguishable from a passing one.
if [ -n "${SWIFTLINT-}" ]; then
    # Resolved to an absolute path: the lint runs happen after a `cd` into the
    # fixture directory, where a relative one would no longer point anywhere.
    case "$SWIFTLINT" in
        /*) ;;
        *) SWIFTLINT="$(cd "$(dirname "$SWIFTLINT")" && pwd)/$(basename "$SWIFTLINT")" ;;
    esac
elif [ -x "$REPO_ROOT/.ci-tools/swiftlint" ]; then
    SWIFTLINT="$REPO_ROOT/.ci-tools/swiftlint"
elif command -v swiftlint >/dev/null 2>&1; then
    SWIFTLINT="$(command -v swiftlint)"
else
    printf '::error::self-test: swiftlint not found. Half of decision 56 is SwiftLint rules, so\n' >&2
    printf '  this cannot report on it. brew install swiftlint, or set SWIFTLINT=<path>.\n' >&2
    exit 2
fi

failed=0
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass() { printf '  ok    %s\n' "$1"; }
fail() {
    printf '  FAIL  %s\n' "$1"
    [ "$#" -gt 1 ] && printf '        %s\n' "$2"
    failed=1
}

# ── part 1: the classes `.swiftlint.yml` owns ───────────────────────────────
printf '\n.swiftlint.yml — the six classes SwiftLint owns\n'

lintdir="$work/lint"
mkdir -p "$lintdir"
# The repository's own config, not a copy written here: a rule that drifted out
# of `.swiftlint.yml` must fail this test rather than pass against a duplicate.
cp "$REPO_ROOT/.swiftlint.yml" "$lintdir/.swiftlint.yml"

cat >"$lintdir/Violating.swift" <<'SWIFT'
import SwiftUI

/// One deliberate violation per class SwiftLint owns.
struct ViolatingView: View {
    /// Body.
    var body: some View {
        VStack(spacing: 12) {
            Text(verbatim: "class 1 — a literal color")
                .foregroundStyle(Color(red: 0.2, green: 0.3, blue: 0.4))
            Text(verbatim: "class 1 — a hex string")
                .foregroundStyle(Color(hex: "#3B82F6"))
            Text(verbatim: "class 2 — an object literal")
                .background(#colorLiteral(red: 1, green: 0, blue: 0, alpha: 1))
            Text(verbatim: "class 4 — a fixed point size")
                .font(.system(size: 13))
            Text(verbatim: "class 5 — a custom font")
                .font(Font.custom("Inter", size: 14))
            Text(verbatim: "class 7 — a hand-placed blur")
                .blur(radius: 8)
            Text(verbatim: "class 8 — a hand-applied glass effect")
                .glassEffect()
        }
        .frame(width: 320, height: 240)
    }
}
SWIFT

cat >"$lintdir/Legitimate.swift" <<'SWIFT'
import SwiftUI

/// The legitimate spelling of every class above. None of it may be reported —
/// a rule that fires here is a rule a developer disables, which decision 56
/// says is worse than no rule.
struct LegitimateView: View {
    /// Body.
    var body: some View {
        VStack {
            Text(verbatim: "a semantic color")
                .foregroundStyle(.primary)
            Text(verbatim: "a macOS text style")
                .font(.largeTitle)
            Text(verbatim: "standard spacing")
                .padding()
        }
        .frame(maxWidth: .infinity)
        .background(.background)
    }
}
SWIFT

lint_output() { # lint_output <file>
    (cd "$lintdir" && "$SWIFTLINT" lint --no-cache --quiet "$1" 2>&1) || true
}

violating_out="$(lint_output Violating.swift)"
legitimate_out="$(lint_output Legitimate.swift)"

# Before any rule is asserted: a rule SwiftLint rejects "falls back to default"
# and silently catches nothing, which is green on a clean tree. That is how an
# invalid `excluded_match_kinds` value shipped once during this file's own
# development, so it is asserted rather than trusted.
if printf '%s' "$violating_out" | grep -q 'Invalid configuration'; then
    fail 'every custom rule is valid configuration' \
        "$(printf '%s' "$violating_out" | grep 'Invalid configuration' | tr '\n' ' ')"
else
    pass 'every custom rule is valid configuration'
fi

expect_rule() { # expect_rule <rule id> <what it covers>
    if printf '%s' "$violating_out" | grep -q "($1)"; then
        pass "$1 — $2"
    else
        fail "$1 — $2" 'not reported on the violating fixture'
    fi
}

expect_rule talos_no_hex_or_literal_color 'class 1, a hex or literal color'
expect_rule discouraged_object_literal    'class 2, #colorLiteral'
expect_rule no_magic_numbers              'class 6, a hardcoded frame or spacing value'
expect_rule talos_no_fixed_point_size     'class 4, a fixed point size'
expect_rule talos_no_font_custom          'class 5, Font.custom'
expect_rule talos_no_hand_placed_blur     'class 7, a hand-placed blur'
expect_rule talos_no_applied_glass_effect 'class 8, a hand-applied glass effect'

# Both spellings of class 1, because the hex string carries no numeric literal
# and `no_magic_numbers` therefore cannot reach it.
if printf '%s' "$violating_out" | grep -q 'talos_no_hex_or_literal_color' &&
    [ "$(printf '%s' "$violating_out" | grep -c 'talos_no_hex_or_literal_color')" -ge 2 ]; then
    pass 'talos_no_hex_or_literal_color — both spellings, Color(red:) and "#RRGGBB"'
else
    fail 'talos_no_hex_or_literal_color — both spellings' \
        'the hex string spelling was not reported; no_magic_numbers cannot reach it'
fi

# The legitimate file must trip no no-values rule. Unrelated rules are ignored:
# this asserts the no-values rules specifically, not the whole catalog.
noisy="$(printf '%s' "$legitimate_out" |
    grep -oE '\((talos_[a-z_]+|no_magic_numbers|discouraged_object_literal)\)' || true)"
if [ -z "$noisy" ]; then
    pass 'the legitimate spelling of every class is silent'
else
    fail 'the legitimate spelling of every class is silent' \
        "$(printf '%s' "$noisy" | sort -u | tr '\n' ' ')"
fi

# ── part 2: the classes `design-guard.sh` owns ──────────────────────────────
printf '\ndesign-guard.sh — the two classes SwiftLint cannot see\n'

expect_reported() { # expect_reported <tree> <check name>
    local out status=0
    out="$("$GUARD" "$1" 2>&1)" || status=$?
    if [ "$status" -eq 0 ]; then
        fail "$2" 'the guard passed a tree it should have failed'
    elif printf '%s' "$out" | grep -q "$2"; then
        pass "$2"
    else
        fail "$2" 'the guard failed, but not on this check'
    fi
}

# class 3 — a bundled color asset. A directory of JSON, so no SwiftLint
# configuration can reach it.
assets="$work/assets"
mkdir -p "$assets/Talos/Assets.xcassets/BrandBlue.colorset"
cat >"$assets/Talos/Assets.xcassets/BrandBlue.colorset/Contents.json" <<'JSON'
{ "colors": [{ "color": { "components": { "blue": "0.96", "red": "0.23" } } }] }
JSON
expect_reported "$assets" 'bundled color asset'

# The escape hatch, uncited — the form decision 56 rejects.
hatch="$work/uncited"
mkdir -p "$hatch/Sources/TalosUI"
cat >"$hatch/Sources/TalosUI/Uncited.swift" <<'SWIFT'
import SwiftUI
// swiftlint:disable:next talos_no_fixed_point_size
let size = Font.system(size: 13)
SWIFT
expect_reported "$hatch" 'suppression cites no SPEC decision'

# The escape hatch, cited — the form decision 56 permits. This is the assertion
# that keeps the hatch a hatch rather than a second prohibition.
cited="$work/cited"
mkdir -p "$cited/Sources/TalosUI"
cat >"$cited/Sources/TalosUI/Cited.swift" <<'SWIFT'
import SwiftUI
// SPEC: https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
// swiftlint:disable:next talos_no_fixed_point_size
let size = Font.system(size: 13)
SWIFT
if "$GUARD" "$cited" >/dev/null 2>&1; then
    pass 'a cited suppression is permitted'
else
    fail 'a cited suppression is permitted' \
        'the guard rejected a suppression that carries its SPEC citation'
fi

# A clean tree must pass, or every assertion above proves only that the guard
# fails on everything.
clean="$work/clean"
mkdir -p "$clean/Sources/TalosUI"
cat >"$clean/Sources/TalosUI/Clean.swift" <<'SWIFT'
import SwiftUI
let style = Font.largeTitle
SWIFT
if "$GUARD" "$clean" >/dev/null 2>&1; then
    pass 'a clean tree passes'
else
    fail 'a clean tree passes' 'the guard reported a violation on a tree with none'
fi

# ── verdict ─────────────────────────────────────────────────────────────────
printf '\n'
if [ "$failed" -eq 0 ]; then
    printf 'self-test: the no-values rule fails on every class and passes on the\n'
    printf '           legitimate spelling of each.\n'
    exit 0
fi

printf '::error::self-test: the no-values rule does not enforce what decision 56 says it does.\n'
printf '  %s\n' 'https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions'
exit 1
