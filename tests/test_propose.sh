#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
P="$DIR/../scripts/propose.sh"
A="$DIR/../scripts/allocate.sh"

sf="$(mktemp)"
"$A" init "$sf" lower_is_better 50 3
"$A" add-arm "$sf" a1 "Delete the TODO lines"
"$A" add-arm "$sf" a2 "Rewrite as DONE"
"$A" update "$sf" a1 0 -3 keep          # a1 best=0
"$A" update "$sf" a2 3 0 discard
"$A" update "$sf" a2 3 0 discard         # a2 stalls
"$A" mark-dead "$sf" a2 "no reduction across 2 tries"

out="$(mktemp -d)/PROPOSAL.md"
"$P" write "$sf" "$out" experiment/c1-a1-c0
body="$(cat "$out")"
assert_contains "$body" "Delete the TODO lines" "names winning approach"
assert_contains "$body" "experiment/c1-a1-c0" "names integration branch"
assert_contains "$body" "git merge" "gives manual merge command"
assert_contains "$body" "no reduction across 2 tries" "lists dead direction + reason"
assert_contains "$body" "PROPOSAL" "has a proposal title"

# missing state errors
"$P" write /no/such/state "$out" b 2>/dev/null; assert_exit 1 $? "missing state errors"
rm -rf "$(dirname "$out")" "$sf"
assert_done
