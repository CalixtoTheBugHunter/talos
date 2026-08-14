#!/usr/bin/env bash
#
# dependency-justification-guard — asserts a PR that adds a NEW dependency
# (not a version bump of an existing one) carries a justification, per this
# issue's acceptance criterion:
#
#   https://github.com/CalixtoTheBugHunter/talos/issues/31
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#talos-is-not-complicated
#
# A version bump — Dependabot's normal job — is deliberately exempt: it is
# detected by comparing the *set* of dependency identifiers at BASE and HEAD,
# not by whether the manifest changed at all. `Package.resolved`/an Action's
# pinned SHA changes on every bump; the identifier set (a package URL, an
# Action name) does not. Requiring justification on every automated bump
# would be the same mistake decision 64 explicitly avoids for the sibling
# `dependency-age-guard`: "this does not slow or disable automatic updates" —
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#dependency-update-age
#
# This is a STEP INSIDE the `lint` stage, not a stage of its own, so it adds
# no required status check on `main` — the same precedent `pr-title-guard`,
# `design-guard`, and `codeowners-guard` set:
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order
#
# Usage:
#   BASE_SHA=<sha> HEAD_SHA=<sha> PR_BODY=<body> tools/dependency-justification-guard/dependency-justification-guard.sh
#   tools/dependency-justification-guard/dependency-justification-guard.sh <base> <head> [repo-root]
#
# BASE_SHA/HEAD_SHA/PR_BODY take priority over the positional arguments, so CI
# can set them from the pull_request event without a large PR_BODY ever
# crossing a shell word-splitting boundary — the same reason pr-title-guard
# takes its inputs this way.
#
# Runs only on the `pull_request` event, gated in ci.yml — a push to `main`
# carries no PR body and no meaningful "base" to diff against.
#
# ── What this does NOT claim ────────────────────────────────────────────────
#
#   - The quality or accuracy of the justification text. It checks that the
#     "New dependency added, justified below" box in the PR template is
#     checked, the same depth pr-title-guard checks a BREAKING CHANGE: footer
#     at — recognized and required, never graded.
#   - A dependency added and removed again within the same PR. The set
#     comparison is BASE vs HEAD only, by design: an intermediate commit is
#     not what merges.

set -euo pipefail

SPEC='https://github.com/CalixtoTheBugHunter/talos/issues/31'

BASE="${BASE_SHA:-${1-}}"
HEAD="${HEAD_SHA:-${2-}}"
REPO_ROOT="${3:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
BODY="${PR_BODY-}"

if [ -z "$BASE" ] || [ -z "$HEAD" ]; then
    printf 'dependency-justification-guard: BASE_SHA and HEAD_SHA are required.\n' >&2
    exit 2
fi

cd "$REPO_ROOT"

# ── Swift package identifiers: the `url:` inside a Package.swift dependency
# declaration. Matched on `url:` rather than the whole `.package(...)` call so
# a multi-line-wrapped declaration (SwiftFormat may wrap a long one) is still
# captured — the URL is what identifies *which* dependency, regardless of how
# its call is laid out.
package_swift_at() { # package_swift_at <ref>
    git show "$1:Package.swift" 2>/dev/null || true
}

swift_deps_at() { # swift_deps_at <ref>
    package_swift_at "$1" | grep -oE 'url:[[:space:]]*"[^"]+"' | sort -u
}

# ── GitHub Action identifiers: the `owner/repo[/path]` before the `@` in a
# `uses:` line, across every workflow file that exists at that ref — a file
# added or removed between BASE and HEAD is handled by construction, since
# each ref's own file list is read from that ref's tree, not the other's.
workflow_files_at() { # workflow_files_at <ref>
    git ls-tree -r "$1" --name-only -- .github/workflows 2>/dev/null | grep -E '\.ya?ml$' || true
}

actions_at() { # actions_at <ref>
    local ref="$1" path
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        git show "$ref:$path" 2>/dev/null
    done < <(workflow_files_at "$ref") \
        | grep -oE 'uses:[[:space:]]*[^@[:space:]]+@' \
        | sed -E 's/^uses:[[:space:]]*//; s/@$//' \
        | sort -u
}

new_swift_deps="$(comm -13 <(swift_deps_at "$BASE") <(swift_deps_at "$HEAD"))"
new_actions="$(comm -13 <(actions_at "$BASE") <(actions_at "$HEAD"))"

if [ -z "$new_swift_deps" ] && [ -z "$new_actions" ]; then
    printf 'dependency-justification-guard: no new dependency identifier between %s and %s.\n' "$BASE" "$HEAD"
    exit 0
fi

printf 'dependency-justification-guard: new dependency identifier(s) found:\n'
[ -n "$new_swift_deps" ] && printf '%s\n' "$new_swift_deps" | sed 's/^/  swift package  /'
[ -n "$new_actions" ] && printf '%s\n' "$new_actions" | sed 's/^/  github action  /'

if printf '%s' "$BODY" | grep -qiE '^-[[:space:]]*\[[xX]\][[:space:]]*New dependency added'; then
    printf 'dependency-justification-guard: the PR body checks "New dependency added, justified below". OK.\n'
    exit 0
fi

printf '::error::dependency-justification-guard: a new dependency was added with no justification in the PR body.\n'
printf '  rule: %s\n' 'Adding a dependency requires justification in the PR, since KISS is a SPEC constraint'
printf '  spec: %s\n' "$SPEC"
printf '  fix:  check "New dependency added, justified below" in the PR template'"'"'s Dependency justification section and fill it in.\n'
exit 1
