#!/usr/bin/env bash
#
# secret-scan — the one gitleaks invocation the CI stage and the pre-commit
# hook both call, so the local answer and CI's answer are the same one:
#
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#toolchain
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#what-is-never-allowlistable
#
# Usage:
#   tools/secret-scan/secret-scan.sh detect [--source <path>] [gitleaks arg]...
#   tools/secret-scan/secret-scan.sh protect-staged [--source <path>]
#
# `detect` scans git history from HEAD (or every commit reached by
# `--log-opts`, passed straight through — that is how a PR job scans only the
# PR's own commits and a scheduled job scans everything). `protect-staged`
# scans the currently staged diff, which is what a pre-commit hook has and all
# it needs: this commit's content, before it leaves the machine.
#
# Both read .gitleaks.toml at the repository root — see that file for what it
# tunes and why. Neither is a substitute for GitHub secret scanning and push
# protection, which this tool does not configure; see the repository's
# security settings and SECURITY.md.

set -euo pipefail

fail() {
  printf 'secret-scan: %s\n' "$1" >&2
  exit 1
}

command -v gitleaks >/dev/null 2>&1 || fail 'gitleaks is not installed. brew install gitleaks'

REPO_ROOT="$(git rev-parse --show-toplevel)"
CONFIG="$REPO_ROOT/.gitleaks.toml"
[ -f "$CONFIG" ] || fail "no committed config at $CONFIG"

mode="${1-}"
[ -n "$mode" ] || fail 'usage: secret-scan.sh <detect|protect-staged> [args...]'
shift

# `--source` defaults to the repository root but is still overridable — the
# self-test needs to point it at a throwaway repo, and passing the same flag
# twice to gitleaks would silently depend on last-flag-wins behavior instead
# of being explicit about it.
source_path="$REPO_ROOT"
extra=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --source)
      source_path="$2"
      shift 2
      ;;
    --source=*)
      source_path="${1#--source=}"
      shift
      ;;
    *)
      extra+=("$1")
      shift
      ;;
  esac
done

case "$mode" in
  detect)
    gitleaks detect --source "$source_path" -c "$CONFIG" --redact -v \
      ${extra[@]+"${extra[@]}"}
    ;;
  protect-staged)
    gitleaks protect --staged --source "$source_path" -c "$CONFIG" --redact -v \
      ${extra[@]+"${extra[@]}"}
    ;;
  *)
    fail "unknown mode: $mode (want: detect | protect-staged)"
    ;;
esac
