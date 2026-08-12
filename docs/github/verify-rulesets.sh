#!/usr/bin/env bash
#
# Asserts that the live GitHub configuration still meets every requirement in
# Engineering Standards § Protection rules on `main`, criterion by criterion.
#
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#protection-rules-on-main
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#ci-pipeline-order
#
# GitHub holds this configuration in its own database, so this script is what makes
# drift visible. Exits non-zero on the first failure, naming the requirement.

set -euo pipefail

REPO="${TALOS_REPO:-CalixtoTheBugHunter/talos}"
failed=0

pass() { printf '  ok    %s\n' "$1"; }
fail() {
  printf '  FAIL  %s\n' "$1"
  printf '        expected: %s\n        actual:   %s\n' "$2" "$3"
  failed=1
}

check() { # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}

command -v gh >/dev/null || { echo "gh is required: https://cli.github.com" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

rulesets=$(gh api "repos/$REPO/rulesets")
main_id=$(printf '%s' "$rulesets" | jq -r '.[] | select(.target=="branch") | .id' | head -1)
tag_id=$(printf '%s' "$rulesets" | jq -r '.[] | select(.target=="tag") | .id' | head -1)

[ -n "$main_id" ] || { echo "no branch ruleset exists on $REPO — nothing to verify" >&2; exit 1; }

main=$(gh api "repos/$REPO/rulesets/$main_id")
rule() { printf '%s' "$main" | jq -r --arg t "$1" '.rules[] | select(.type==$t) | .type // empty'; }
param() { printf '%s' "$main" | jq -r --arg t "$1" --arg p "$2" \
  '.rules[] | select(.type==$t) | .parameters[$p] // empty'; }

echo "Branch ruleset on the default branch of $REPO"

check "enforcement is active" "active" "$(printf '%s' "$main" | jq -r .enforcement)"
check "applies to the default branch" "~DEFAULT_BRANCH" \
  "$(printf '%s' "$main" | jq -r '.conditions.ref_name.include[0]')"

# "No direct pushes. No force-push. No branch deletion."
check "AC1 pull request required (blocks direct pushes)" "pull_request" "$(rule pull_request)"
check "AC1 force-push blocked" "non_fast_forward" "$(rule non_fast_forward)"
check "AC1 branch deletion blocked" "deletion" "$(rule deletion)"

# "Pull request required, with 1 approval."
check "AC2 one approving review required" "1" "$(param pull_request required_approving_review_count)"

# "All required status checks green." — the six names in § CI pipeline order.
actual_checks=$(printf '%s' "$main" | jq -r \
  '[.rules[] | select(.type=="required_status_checks")
    | .parameters.required_status_checks[].context] | sort | join(",")')
check "AC3 the six required status checks" "a11y,build,lint,perf-budget,spec-guard,test" "$actual_checks"

# "Linear history — squash-merge only."
check "AC4 linear history required" "required_linear_history" "$(rule required_linear_history)"

# "Merge commits and rebase-merge are disabled." — a repository setting, not a ruleset rule.
merge=$(gh api "repos/$REPO")
check "AC5 squash-merge enabled" "true" "$(printf '%s' "$merge" | jq -r .allow_squash_merge)"
check "AC5 merge commits disabled" "false" "$(printf '%s' "$merge" | jq -r .allow_merge_commit)"
check "AC5 rebase-merge disabled" "false" "$(printf '%s' "$merge" | jq -r .allow_rebase_merge)"

# "Conversation resolution required before merge."
check "AC6 conversation resolution required" "true" \
  "$(param pull_request required_review_thread_resolution)"

# "Signed commits and signed tags required."
check "AC7 signed commits required" "required_signatures" "$(rule required_signatures)"

# Decision 48 — a new commit dismisses an existing approval.
check "AC8 stale approvals dismissed on push" "true" "$(param pull_request dismiss_stale_reviews_on_push)"
check "AC8 the most recent push must be approved" "true" \
  "$(param pull_request require_last_push_approval)"

# Decision 62 — a code owner's approval is required on the high-risk paths.
check "decision 62 code owner review required" "true" \
  "$(param pull_request require_code_owner_review)"

# Decision 46 — the owner is not bound by the list above.
check "decision 46 owner bypass present" "always" \
  "$(printf '%s' "$main" | jq -r '[.bypass_actors[] | select(.actor_type=="RepositoryRole") | .bypass_mode][0] // empty')"

echo
echo "Tag ruleset (signed tags required)"
if [ -z "$tag_id" ]; then
  fail "AC7 signed tags required" "a ruleset with target=tag" "none exists"
else
  tags=$(gh api "repos/$REPO/rulesets/$tag_id")
  check "enforcement is active" "active" "$(printf '%s' "$tags" | jq -r .enforcement)"
  check "AC7 signed tags required" "required_signatures" \
    "$(printf '%s' "$tags" | jq -r '.rules[] | select(.type=="required_signatures") | .type // empty')"
  check "tag deletion blocked" "deletion" \
    "$(printf '%s' "$tags" | jq -r '.rules[] | select(.type=="deletion") | .type // empty')"
  check "tag overwrite blocked" "non_fast_forward" \
    "$(printf '%s' "$tags" | jq -r '.rules[] | select(.type=="non_fast_forward") | .type // empty')"
fi

echo
if [ "$failed" -eq 0 ]; then
  echo "All requirements met."
else
  echo "Drift found. The wiki wins: fix the configuration, or fix the SPEC in the same PR." >&2
fi
exit "$failed"
