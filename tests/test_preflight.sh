#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
SHADOW_PREFLIGHT_LIB=1 . "$DIR/../scripts/preflight.sh"

out="$(check_tool git git)"; assert_exit 0 $? "git present returns 0"; assert_contains "$out" "[ok] git" "git ok line"
out2="$(check_tool Frobnicator definitely-not-a-real-binary-xyz)"; assert_exit 1 $? "missing returns 1"
assert_contains "$out2" "[MISSING] Frobnicator" "missing line"
# alt command fallback
out3="$(check_tool memsearch definitely-missing-xyz git)"; assert_exit 0 $? "alt fallback found"
# gh is optional: a preflight run must NOT fail solely because gh is missing.
# Simulate by checking the required list excludes gh — run preflight with a PATH that has git/jq/claude/uvx but no gh.
# (Lightweight check: the script's required block must not reference gh with `|| rc=1`.)
pf="$DIR/../scripts/preflight.sh"
assert_eq "0" "$(grep -c 'check_tool gh gh .*rc=1' "$pf" || true)" "gh not in required-fail set"
assert_contains "$(cat "$pf")" "proposal-only" "gh reported as optional/proposal-only"
assert_done
