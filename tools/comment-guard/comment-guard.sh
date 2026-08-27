#!/usr/bin/env bash
#
# comment-guard — the two enumerable bans decision 70 named but left
# unenforced (a TODO/FIXME/XXX marker and an issue or PR reference, each on a
# full-line code comment), plus the DocC abstract-length convention decision
# 76 adds: a `///` doc comment's first line is a plain-text summary, at most
# 150 characters, per DocC's own writing guidance.
#
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#code-comments-explain-the-non-obvious-not-the-history
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
#
# Usage:
#   tools/comment-guard/comment-guard.sh          # scan this repository's tracked Swift files
#   tools/comment-guard/comment-guard.sh <path>   # scan every Swift file under <path>
#
# The second form exists for self-test.sh, which generates a deliberately
# violating tree outside the repository — a TODO or an issue reference in a
# committed fixture would itself be the violation this checks for.
#
# This is a STEP INSIDE the `lint` stage, not a stage of its own, so it adds no
# required status check on `main`:
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order
#
# ── What this check does NOT claim ──────────────────────────────────────────
#
# Stated because a green run is otherwise read as a claim it never made:
#
#   - It does not judge whether a comment is redundant, narrates history in
#     free prose, or restates an identifier's own name — decision 70's general
#     test ("would a reader lose anything if this were deleted") is not
#     mechanically checkable and stays enforced by `review-pr`.
#   - It does not cap a doc comment's total length, only its first line.
#     `AgentAdapter.swift`'s own protocol documentation legitimately runs past
#     20 lines with `- Parameters:`/`- Returns:`/`- Throws:` sections; a
#     blanket cap would flag accepted precedent rather than AI-produced bloat.
#   - It only scans a full-line comment — one whose line, trimmed, starts with
#     `//` — not a trailing comment after code on the same line. A trailing
#     comment can follow a string literal containing `//`, which this check
#     cannot distinguish from a real comment start without a Swift parser.
#   - It scans `*.swift` files only. Decision 70 is scoped to a "code
#     comment"; this repository's own tooling (shell scripts, workflow files)
#     follows a different, already-established convention that cites issues
#     freely in its own header comments.

set -euo pipefail

STANDARDS='https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#code-comments-explain-the-non-obvious-not-the-history'
DECISION='https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions'

ABSTRACT_MAX=150

hits=0

report() { # report <check> <evidence>
    hits=$((hits + 1))
    printf '::error::comment-guard: %s\n' "$1"
    printf '%s\n' "$2" | sed 's/^/  /'
}

SCAN_ROOT="${1-}"
if [ -n "$SCAN_ROOT" ]; then
    [ -d "$SCAN_ROOT" ] || { printf 'comment-guard: not a directory: %s\n' "$SCAN_ROOT" >&2; exit 2; }
    BASE="$(cd "$SCAN_ROOT" && pwd)"
    MODE='tree'
else
    command -v git >/dev/null || { echo 'comment-guard: git is required' >&2; exit 2; }
    BASE="$(git rev-parse --show-toplevel)"
    MODE='repository'
fi
cd "$BASE"

list_files() {
    if [ "$MODE" = 'tree' ]; then
        find . -type f -name '*.swift' -print0
    else
        git ls-files -z -- '*.swift'
    fi
}

swift_files=()
while IFS= read -r -d '' path; do
    swift_files+=("${path#./}")
done < <(list_files)

printf 'comment-guard: %s mode, %d Swift file(s)\n\n' "$MODE" "${#swift_files[@]}"

# ── 1 & 2. TODO/FIXME/XXX and an issue or PR reference, on a full-line comment
todo_hits=''
ref_hits=''
for path in ${swift_files[@]+"${swift_files[@]}"}; do
    found="$(awk '
        {
            line = $0
            trimmed = line
            sub(/^[ \t]*/, "", trimmed)
            if (trimmed ~ /^\/\//) {
                if (trimmed ~ /(^|[^A-Za-z])(TODO|FIXME|XXX)([^A-Za-z]|$)/) {
                    printf "TODO|%s:%d: %s\n", FILENAME, FNR, trimmed
                }
                if (trimmed ~ /(^|[^A-Za-z0-9_#])#[0-9]+([^0-9A-Za-z_]|$)/ ||
                    trimmed ~ /github\.com\/[^ ]+\/(issues|pull)\/[0-9]+/) {
                    printf "REF|%s:%d: %s\n", FILENAME, FNR, trimmed
                }
            }
        }
    ' "$path")"
    [ -n "$found" ] && while IFS='|' read -r kind evidence; do
        case "$kind" in
            TODO) todo_hits="${todo_hits}${evidence}"$'\n' ;;
            REF) ref_hits="${ref_hits}${evidence}"$'\n' ;;
        esac
    done <<<"$found"
done

if [ -n "$todo_hits" ]; then
    report 'a TODO, FIXME, or XXX marker in a code comment' \
        "Decision 70: that history belongs to the commit and the PR description, not the code.
$STANDARDS
$DECISION

$(printf '%s' "$todo_hits" | sed '/^$/d')"
fi

if [ -n "$ref_hits" ]; then
    report 'an issue or PR reference in a code comment' \
        "Decision 70: an issue number or a PR reference is a finding under this rule, not a style preference.
$STANDARDS
$DECISION

$(printf '%s' "$ref_hits" | sed '/^$/d')"
fi

# ── 3. A `///` doc comment's first line (the DocC abstract) over 150 characters
abstract_hits=''
for path in ${swift_files[@]+"${swift_files[@]}"}; do
    found="$(awk -v max="$ABSTRACT_MAX" '
        {
            line = $0
            trimmed = line
            sub(/^[ \t]*/, "", trimmed)
            isDoc = (trimmed ~ /^\/\/\//)
            if (isDoc && !prevDoc) {
                text = trimmed
                sub(/^\/\/\//, "", text)
                sub(/^[ \t]/, "", text)
                if (length(text) > max) {
                    printf "%s:%d: abstract is %d characters (max %d): %s\n", FILENAME, FNR, length(text), max, text
                }
            }
            prevDoc = isDoc
        }
    ' "$path")"
    [ -n "$found" ] && abstract_hits="${abstract_hits}${found}"$'\n'
done
abstract_hits="$(printf '%s' "$abstract_hits" | sed '/^$/d')"
if [ -n "$abstract_hits" ]; then
    report "a doc comment's first line is over $ABSTRACT_MAX characters — DocC's own abstract convention" \
        "$STANDARDS
$DECISION

$abstract_hits"
fi

if [ "$hits" -eq 0 ]; then
    printf 'comment-guard: no violations across %d Swift file(s).\n' "${#swift_files[@]}"
    exit 0
fi

printf '::error::comment-guard: %d check(s) failed.\n' "$hits"
printf '  %s\n  %s\n' "$STANDARDS" "$DECISION"
exit 1
