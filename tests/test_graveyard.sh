#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
G="$DIR/../scripts/graveyard.sh"

gv="$(mktemp -d)/graveyard.md"
"$G" append "$gv" a1 "delete TODO lines" "every variant matched baseline; no reduction"
"$G" append "$gv" a2 "rewrite as DONE" "regressed metric on 2/2 tries"
body="$(cat "$gv")"
assert_contains "$body" "# Graveyard" "has header"
assert_contains "$body" "## a1: delete TODO lines" "entry a1"
assert_contains "$body" "no reduction" "a1 reason"
assert_contains "$body" "## a2: rewrite as DONE" "entry a2"
# header appears exactly once
assert_eq "1" "$(grep -c '^# Graveyard' "$gv")" "header written once"
rm -rf "$(dirname "$gv")"
assert_done
