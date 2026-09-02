#!/usr/bin/env bash
#
# dependency-age-guard — asserts a PR that bumps a dependency — a pinned
# GitHub Action SHA, or a Swift package's declared version requirement — to a
# version published less than a minimum age ago fails, per decision 64:
#
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#dependency-update-age
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
#   https://github.com/CalixtoTheBugHunter/talos/issues/178
#
# A compromised maintainer account or a hijacked publish ships a malicious
# version that looks like a routine update; holding the MERGE (not the PR)
# until the wider ecosystem has had time to notice is the mechanism this
# check enforces. Dependabot's schedule and PR-opening are unaffected — only
# the merge is gated.
#
# "Published" is read from GitHub's own commit-date-for-a-ref answer:
#   gh api repos/<owner>/<repo>/commits/<ref>
# A GitHub Action already pins a full commit SHA (a `ref` the endpoint takes
# directly). A Swift package pins a version REQUIREMENT in Package.swift, not
# a resolved commit: Package.resolved records the exact resolved revision,
# but this repository's .gitignore excludes it — Package.resolved is never
# committed, so there is no ref to diff it at. The same endpoint also accepts
# a tag name as `ref`, so the Swift side is checked by asking for the
# declared version (tried bare, then with a `v` prefix) rather than a SHA.
#
# MIN_AGE_HOURS is a required input, never a number embedded below — decision
# 64's "single configured value" lives in .github/workflows/ci.yml's
# DEPENDENCY_MIN_AGE_HOURS, the same way SWIFTLINT_VERSION does for the
# linters this job installs.
#
# This is a STEP INSIDE the `lint` stage, not a stage of its own, so it adds
# no required status check on `main` — the same precedent
# `dependency-justification-guard`, `workflow-hardening-guard`, and
# `codeowners-guard` set, per decision 64.
#
# Usage:
#   BASE_SHA=<sha> HEAD_SHA=<sha> MIN_AGE_HOURS=<n> tools/dependency-age-guard/dependency-age-guard.sh
#   MIN_AGE_HOURS=<n> tools/dependency-age-guard/dependency-age-guard.sh <base> <head> [repo-root]
#
# Runs only on the `pull_request` event, gated in ci.yml — a push to `main`
# carries no meaningful "base" to diff a bump against.
#
# ── What this does NOT claim ────────────────────────────────────────────────
#
#   - A Swift package pinned by `branch:` or `revision:` rather than a
#     version requirement (`from:`/`exact:`/`.upToNextMajor`/`.upToNextMinor`).
#     There is no version to age-check; every current dependency uses `from:`.
#   - A dependency hosted anywhere other than github.com. Every current
#     dependency is; a non-GitHub location is reported as unresolvable rather
#     than silently passed.
#   - A `Package.swift` whose `.package(` call nests another function call
#     spanning multiple entries in a way the per-`.package(`-chunk parser
#     below cannot separate. This repository's manifest does not do that; see
#     README.md for the parser's exact boundary.
#   - Protection against a crafted `committer.date` on the commit a tag
#     resolves to — see README.md § Why commit date, not a Release's
#     published_at.

set -euo pipefail

SPEC='https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#dependency-update-age'

BASE="${BASE_SHA:-${1-}}"
HEAD="${HEAD_SHA:-${2-}}"
REPO_ROOT="${3:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
MIN_AGE_HOURS="${MIN_AGE_HOURS-}"

if [ -z "$BASE" ] || [ -z "$HEAD" ]; then
    printf 'dependency-age-guard: BASE_SHA and HEAD_SHA are required.\n' >&2
    exit 2
fi

if [ -z "$MIN_AGE_HOURS" ]; then
    printf 'dependency-age-guard: MIN_AGE_HOURS is required — decision 64 holds the threshold as\n' >&2
    printf 'a single configured value, never a number embedded in this script.\n' >&2
    printf '  %s\n' "$SPEC" >&2
    exit 2
fi

case "$MIN_AGE_HOURS" in
    '' | *[!0-9]*)
        printf 'dependency-age-guard: MIN_AGE_HOURS must be a non-negative integer, got %q\n' "$MIN_AGE_HOURS" >&2
        exit 2
        ;;
esac

command -v gh >/dev/null 2>&1 || {
    printf 'dependency-age-guard: gh is required to look up when a pinned commit was published.\n' >&2
    printf 'A missing tool is a failure, not a skip. https://cli.github.com\n' >&2
    exit 2
}
command -v jq >/dev/null 2>&1 || {
    printf 'dependency-age-guard: jq is required to read the gh api response.\n' >&2
    exit 2
}

cd "$REPO_ROOT"

# ── GitHub Action pins: "name<TAB>sha" for every remote `uses:` line pinned to
# a full commit SHA, across every workflow file that exists at that ref.
workflow_files_at() { # workflow_files_at <ref>
    git ls-tree -r "$1" --name-only -- .github/workflows 2>/dev/null | grep -E '\.ya?ml$' || true
}

action_pins_at() { # action_pins_at <ref> -> "name<TAB>sha"
    local ref="$1" path
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        git show "$ref:$path" 2>/dev/null
    done < <(workflow_files_at "$ref") \
        | grep -oE 'uses:[[:space:]]*[^@[:space:]]+@[0-9a-fA-F]{40}' \
        | sed -E 's/^uses:[[:space:]]*//; s/@/\t/' \
        | sort -u
}

# ── Swift package requirements: "url<TAB>version" for every version-pinned
# `.package(url: "...", from|exact|.upToNextMajor|.upToNextMinor: "X.Y.Z")`
# declaration in Package.swift at that ref. Chunked per `.package(` occurrence
# so a wrapped, multi-line declaration is still one unit — the same reasoning
# tools/dependency-justification-guard's `swift_deps_at` gives for capturing
# the url regardless of layout. A chunk stops at the next `.package(`, a bare
# `]` (the dependencies array closing), or `targets:` (the next manifest key
# at this nesting) — see the header note on what a nested call inside
# `.package(` does to this.
swift_deps_at() { # swift_deps_at <ref> -> "url<TAB>version"
    local ref="$1" chunk url rest version
    git show "$ref:Package.swift" 2>/dev/null | awk '
        /\.package\(/ {
            if (chunk != "") print chunk
            chunk = $0
            next
        }
        /^[[:space:]]*\]/ || /targets:/ {
            if (chunk != "") { print chunk; chunk = "" }
            next
        }
        chunk != "" { chunk = chunk " " $0 }
        END { if (chunk != "") print chunk }
    ' | while IFS= read -r chunk; do
        url="$(printf '%s\n' "$chunk" | grep -oE 'url:[[:space:]]*"[^"]+"' | sed -E 's/^url:[[:space:]]*"//; s/"$//')"
        [ -n "$url" ] || continue
        rest="$(printf '%s\n' "$chunk" | sed -E 's/url:[[:space:]]*"[^"]+"//')"
        version="$(printf '%s\n' "$rest" | grep -oE '"[0-9]+\.[0-9]+(\.[0-9]+)?[A-Za-z0-9.+-]*"' | head -1 | tr -d '"')"
        [ -n "$version" ] || continue
        printf '%s\t%s\n' "$url" "$version"
    done | sort -u
}

# ── the left-join: every key present at HEAD whose sha differs from BASE's
# (or is absent from BASE). AWK's own arrays, not bash's — this repository's
# scripts run on macOS's default bash, which has no `declare -A`.
changed_pins() { # changed_pins <base-tsv> <head-tsv>
    awk -F'\t' -v OFS='\t' '
        NR == FNR { base[$1] = $2; next }
        !($1 in base) || base[$1] != $2 { print }
    ' "$1" "$2"
}

base_actions="$(mktemp)"
head_actions="$(mktemp)"
base_swift="$(mktemp)"
head_swift="$(mktemp)"
trap 'rm -f "$base_actions" "$head_actions" "$base_swift" "$head_swift"' EXIT

action_pins_at "$BASE" >"$base_actions"
action_pins_at "$HEAD" >"$head_actions"
swift_deps_at "$BASE" >"$base_swift"
swift_deps_at "$HEAD" >"$head_swift"

changed_actions="$(changed_pins "$base_actions" "$head_actions")"
changed_swift="$(changed_pins "$base_swift" "$head_swift")"

if [ -z "$changed_actions" ] && [ -z "$changed_swift" ]; then
    printf "dependency-age-guard: no dependency's resolved version changed between %s and %s.\n" "$BASE" "$HEAD"
    exit 0
fi

hits=0

report() { # report <what> <ref> <owner/repo> <detail>
    hits=$((hits + 1))
    printf '::error::dependency-age-guard: %s\n' "$1"
    printf '  ref: %s (%s)\n' "$2" "$3"
    printf '  rule: A dependency bumped to a version published less than %s hour(s) ago is blocked from merging\n' "$MIN_AGE_HOURS"
    printf '  spec: %s\n' "$SPEC"
    [ -z "${4-}" ] || printf '%s\n' "$4" | sed 's/^/  /'
}

owner_repo_from_action() { # owner_repo_from_action <name>
    printf '%s\n' "$1" | cut -d/ -f1-2
}

owner_repo_from_location() { # owner_repo_from_location <git url>
    case "$1" in
        *github.com*)
            printf '%s\n' "$1" | sed -E 's#^.*github\.com[:/]##; s#\.git$##'
            ;;
        *)
            printf ''
            ;;
    esac
}

now_epoch="$(date -u +%s)"

# commit_date_for_ref <owner/repo> <ref> — echoes the ISO8601 committer date
# GitHub reports for <ref> (a SHA, tag, or branch), or fails.
commit_date_for_ref() { # commit_date_for_ref <owner/repo> <ref>
    gh api "repos/$1/commits/$2" --jq '.commit.committer.date' 2>&1
}

# check_pin <label> <owner/repo> <ref> [ref...] — tries each candidate ref in
# order (a Swift version requirement may be tagged bare or `v`-prefixed) and
# checks the age of the first one GitHub resolves.
check_pin() { # check_pin <label> <owner/repo> <ref> [ref...]
    local label="$1" owner_repo="$2" out status=0 commit_date commit_epoch age_hours tried=''
    shift 2

    if [ -z "$owner_repo" ]; then
        report "$label: cannot resolve a GitHub owner/repo to look up" "$*" 'unresolvable' \
            'not a github.com location — see README.md for what this does NOT claim'
        return
    fi

    for ref in "$@"; do
        tried="$tried $ref"
        out="$(commit_date_for_ref "$owner_repo" "$ref")" && status=0 || status=$?
        [ "$status" -eq 0 ] && break
    done

    if [ "$status" -ne 0 ]; then
        report "$label: could not look up the publish date for any of:$tried" "$*" "$owner_repo" "$out"
        return
    fi
    commit_date="$out"

    commit_epoch="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$commit_date" '+%s' 2>/dev/null)" || {
        report "$label: could not parse the commit date returned by GitHub" "$ref" "$owner_repo" "got: $commit_date"
        return
    }

    age_hours=$(((now_epoch - commit_epoch) / 3600))

    if [ "$age_hours" -lt "$MIN_AGE_HOURS" ]; then
        report "$label: published $age_hours hour(s) ago, younger than the $MIN_AGE_HOURS hour minimum" \
            "$ref" "$owner_repo" "published: $commit_date"
    else
        printf 'dependency-age-guard: %s — published %s hour(s) ago (>= %s). OK.\n' "$label" "$age_hours" "$MIN_AGE_HOURS"
    fi
}

if [ -n "$changed_actions" ]; then
    while IFS=$'\t' read -r name sha; do
        [ -n "$name" ] || continue
        check_pin "github action $name" "$(owner_repo_from_action "$name")" "$sha"
    done <<<"$changed_actions"
fi

if [ -n "$changed_swift" ]; then
    while IFS=$'\t' read -r url version; do
        [ -n "$url" ] || continue
        check_pin "swift package $url@$version" "$(owner_repo_from_location "$url")" "$version" "v$version"
    done <<<"$changed_swift"
fi

if [ "$hits" -eq 0 ]; then
    printf 'dependency-age-guard: every changed dependency has aged past %s hour(s).\n' "$MIN_AGE_HOURS"
    exit 0
fi

printf '::error::dependency-age-guard: %d dependency bump(s) are too fresh to merge.\n' "$hits"
printf '  %s\n' "$SPEC"
exit 1
