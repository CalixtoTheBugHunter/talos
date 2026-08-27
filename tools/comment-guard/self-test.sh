#!/usr/bin/env bash
#
# Confirms `comment-guard.sh` actually fails on a deliberate violation of each
# of its four checks, and passes on the legitimate spelling. A guard nobody
# tested is indistinguishable from a guard that matches nothing, and both are
# green.
#
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Engineering-Standards#code-comments-explain-the-non-obvious-not-the-history
#   https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
#
# The violating fixtures are GENERATED, never committed. A TODO or an issue
# reference in a committed test fixture is itself the violation this check
# exists to catch, and there is no allowlist to exempt its path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD="$SCRIPT_DIR/comment-guard.sh"

failed=0
pass() { printf '  ok    %s\n' "$1"; }
fail() {
    failed=1
    printf '  FAIL  %s\n' "$1"
    [ "$#" -gt 1 ] && printf '        %s\n' "$2"
}

run_case() { # run_case <label> <expect: pass|fail> <file content>
    local label="$1" expect="$2" content="$3"
    local dir out status=0
    dir="$(mktemp -d)"
    trap 'rm -rf "$dir"' RETURN
    printf '%s\n' "$content" > "$dir/Fixture.swift"
    out="$("$GUARD" "$dir" 2>&1)" || status=$?
    if [ "$expect" = 'pass' ]; then
        if [ "$status" -eq 0 ]; then pass "$label"; else fail "$label" "$out"; fi
    else
        if [ "$status" -ne 0 ]; then pass "$label"; else fail "$label" "$out"; fi
    fi
    rm -rf "$dir"
    trap - RETURN
}

printf '\nTODO / FIXME / XXX on a full-line comment\n'
run_case 'a TODO marker fails'  fail 'import Foundation

// TODO: revisit this after the next release.
struct Thing {}'
run_case 'a FIXME marker fails' fail 'import Foundation

// FIXME: this is broken under load.
struct Thing {}'
run_case 'the word "todolist" in a comment passes' pass 'import Foundation

// The full todolist for this feature lives on the board, not here.
struct Thing {}'

printf '\nissue and PR references on a full-line comment\n'
run_case 'a bare "#52" fails' fail 'import Foundation

// Asserted against a real process, see #52 for the fixture.
struct Thing {}'
run_case 'an issues URL fails' fail 'import Foundation

/// https://github.com/CalixtoTheBugHunter/talos/issues/52
struct Thing {}'
run_case 'a pull URL fails' fail 'import Foundation

// Reviewed in https://github.com/CalixtoTheBugHunter/talos/pull/200.
struct Thing {}'
run_case 'a wiki anchor URL passes' pass 'import Foundation

/// https://github.com/CalixtoTheBugHunter/talos/wiki/Decision-Log#engineering-decisions
struct Thing {}'
run_case 'a hex color in a comment passes' pass 'import Foundation

// Never #FF0000 or any other literal — see the design system.
struct Thing {}'

printf '\nDocC abstract length (max 150 characters)\n'
run_case 'a 151-character abstract fails' fail "import Foundation

/// $(printf 'a%.0s' $(seq 1 151))
struct Thing {}"
run_case 'a 150-character abstract passes' pass "import Foundation

/// $(printf 'a%.0s' $(seq 1 150))
struct Thing {}"
run_case 'a long Discussion paragraph after a short abstract passes' pass "import Foundation

/// Short abstract.
///
/// $(printf 'a%.0s' $(seq 1 200))
struct Thing {}"

printf '\na plain `//` block directly adjacent to a `///` doc comment\n'
run_case 'a banner immediately before a doc comment fails' fail 'import Foundation

// Some rationale that belongs inside the doc comment below.
/// The abstract.
struct Thing {}'
run_case 'a banner separated by a blank line still fails' fail 'import Foundation

// Some rationale that belongs inside the doc comment below.

/// The abstract.
struct Thing {}'
run_case 'a MARK-only block before a doc comment passes' pass 'import Foundation

struct Container {
    // MARK: - Some section

    /// The abstract.
    func thing() {}
}'
run_case 'a banner with no doc comment beneath it passes' pass 'import Foundation

// A plain comment on its own, nothing documented right after it.
struct Thing {
    let value: Int
}'
run_case 'a doc comment with no banner above it passes' pass 'import Foundation

/// The abstract, nothing above it.
struct Thing {}'

printf '\nclean fixture over the whole check passes\n'
run_case 'a normal doc comment passes' pass 'import Foundation

/// One clean sentence, well under the limit.
struct Thing {}'

echo
if [ "$failed" -eq 0 ]; then
    echo 'comment-guard self-test: all cases passed.'
    exit 0
fi
echo '::error::comment-guard self-test: at least one case failed.'
exit 1
