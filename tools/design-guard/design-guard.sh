#!/usr/bin/env bash
#
# design-guard — the two halves of the no-values rule that SwiftLint's
# `custom_rules` structurally cannot check.
#
# The rules it enforces live on the wiki and are not restated here; each check
# below carries the page and anchor that binds it, and prints them on failure:
#
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Design-System#the-platform-is-the-design-system
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#how-the-gate-is-checked
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
#
# Usage:
#   tools/design-guard/design-guard.sh          # scan this repository's tracked files
#   tools/design-guard/design-guard.sh <path>   # scan every file under <path>
#
# The second form exists for `self-test.sh`, which generates a deliberately
# violating tree outside the repository. Committing such a fixture is not an
# option: a hex literal or a bundled color asset in a test fixture is itself the
# violation, per decision 56.
#
# This is a STEP INSIDE the `lint` stage, not a stage of its own, so it adds no
# required status check on `main`:
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order
#
# ── What this check does NOT claim ──────────────────────────────────────────
#
# Stated because a green run is otherwise read as a claim it never made:
#
#   - It does not check the six classes `.swiftlint.yml` owns — a hex or literal
#     color, a fixed point size, `Font.custom`, a hand-placed blur, a glass
#     effect, and `#colorLiteral`. Those are SwiftLint rules, and a green run
#     here says nothing about them.
#   - It does not check a hardcoded frame or spacing value. That is
#     `no_magic_numbers`, and its loophole — a named constant holding a
#     hard-coded number — is review-enforced by decision 56, not checked here.
#   - It does not scan `tools/design-guard/` — see "the one exclusion" below.
#   - It reads a suppression's *citation*, never whether the cited decision
#     actually permits the suppression. That is a reviewer's judgement, and the
#     citation is what makes it a short one.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# The one exclusion, and why it is not an allowlist entry.
#
# A grep for `swiftlint:disable` necessarily contains that string, and so does
# the self-test that writes the fixture. The scanner therefore cannot scan its
# own pattern table. That is structural — not a judgement that some violation
# here is acceptable.
GUARD_DIR="tools/design-guard"

# ── SPEC references, printed on failure ─────────────────────────────────────
DESIGN='https://github.com/CalixtoTheBugHunter/talos/wiki/Design-System#the-platform-is-the-design-system'
GATE='https://github.com/CalixtoTheBugHunter/talos/wiki/Foundations-Accessibility#how-the-gate-is-checked'
DECISION='https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions'

# The rule IDs decision 56 assigns to a no-values class. A suppression of any of
# them is the escape hatch, so it is the set check 2 brakes. `no_magic_numbers`
# and `discouraged_object_literal` are here because decision 56 credits them
# with a class each — suppressing one drops that class as surely as suppressing
# a `talos_` rule does.
GUARDED_RULES='talos_no_hex_or_literal_color|talos_no_fixed_point_size|talos_no_font_custom|talos_no_hand_placed_blur|talos_no_applied_glass_effect|no_magic_numbers|discouraged_object_literal'

# The citation a suppression must carry, on the line immediately before it.
CITATION='//[[:space:]]*SPEC:[[:space:]]*https://github\.com/CalixtoTheBugHunter/talos/wiki/'

hits=0

report() { # report <check> <rule> <spec url> <evidence>
    hits=$((hits + 1))
    printf '::error::design-guard: %s\n' "$1"
    printf '  rule:     %s\n' "$2"
    printf '  spec:     %s\n' "$3"
    printf '  decision: %s\n' "$DECISION"
    printf '%s\n\n' "$4" | sed 's/^/  /'
}

# ── the scan surface ────────────────────────────────────────────────────────
SCAN_ROOT="${1-}"
if [ -n "$SCAN_ROOT" ]; then
    [ -d "$SCAN_ROOT" ] || { printf 'design-guard: not a directory: %s\n' "$SCAN_ROOT" >&2; exit 2; }
    BASE="$(cd "$SCAN_ROOT" && pwd)"
    MODE='tree'
else
    command -v git >/dev/null || { echo 'design-guard: git is required' >&2; exit 2; }
    BASE="$(git rev-parse --show-toplevel)"
    MODE='repository'
fi
cd "$BASE"

list_files() {
    if [ "$MODE" = 'tree' ]; then
        find . -type f -print0
    else
        git ls-files -z
    fi
}

all_files=()
swift_files=()

while IFS= read -r -d '' path; do
    path="${path#./}"
    case "$path" in "$GUARD_DIR"/*) continue ;; esac
    all_files+=("$path")
    case "$path" in *.swift) swift_files+=("$path") ;; esac
done < <(list_files)

printf 'design-guard: %s mode, %d file(s), %d Swift file(s)\n\n' \
    "$MODE" "${#all_files[@]}" "${#swift_files[@]}"

# ── 1. Bundled color assets ─────────────────────────────────────────────────
# "Talos never defines ... A brand palette, a hex literal, a bundled color
# asset" — § The platform is the design system. A `.colorset` is a directory of
# JSON, not a Swift file, so SwiftLint cannot see one however it is configured.
# This check is the reason decision 56 is not configuration alone.
colorsets=()
for path in ${all_files[@]+"${all_files[@]}"}; do
    case "$path" in *.colorset/*) colorsets+=("$path") ;; esac
done
if [ "${#colorsets[@]}" -gt 0 ]; then
    report 'bundled color asset' \
        'Talos never defines a brand palette, a hex literal, or a bundled color asset' \
        "$DESIGN" \
        "$(printf '%s\n' "${colorsets[@]}")"
fi

# ── 2. The escape hatch cites a SPEC decision ───────────────────────────────
# Decision 56: a suppression is legal only with a `// SPEC: <wiki URL>` citation
# on the line immediately before it. The hatch is braked rather than removed
# because `swiftlint:disable` suppresses a custom rule whether or not a hatch is
# decided — so the only available choice was cited or invisible.
uncited=''
for path in ${swift_files[@]+"${swift_files[@]}"}; do
    found="$(awk -v rules="$GUARDED_RULES" -v citation="$CITATION" -v file="$path" '
        {
            if ($0 ~ /swiftlint:disable/ && $0 ~ "(" rules ")") {
                if (prev !~ citation) printf "%s:%d: %s\n", file, NR, $0
            }
            prev = $0
        }
    ' "$path")"
    [ -n "$found" ] && uncited="${uncited}${found}"$'\n'
done
uncited="$(printf '%s' "$uncited" | sed '/^$/d')"
if [ -n "$uncited" ]; then
    report 'suppression cites no SPEC decision' \
        'A suppression of a no-values rule needs a `// SPEC: <wiki URL>` citation on the line immediately before it' \
        "$GATE" \
        "$uncited"
fi

# ── verdict ─────────────────────────────────────────────────────────────────
if [ "$hits" -eq 0 ]; then
    printf 'design-guard: no violations across %d file(s).\n' "${#all_files[@]}"
    exit 0
fi

printf '::error::design-guard: %d check(s) failed.\n' "$hits"
printf 'The no-values rule is a hard constraint: the platform is the design system, and\n'
printf 'a hex literal or a fixed point size is a defect rather than a preference.\n'
printf '  %s\n  %s\n' "$DESIGN" "$DECISION"
exit 1
