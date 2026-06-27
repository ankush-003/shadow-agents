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
assert_done
