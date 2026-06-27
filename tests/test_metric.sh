#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
M="$DIR/../scripts/metric.sh"

assert_eq "0.9979" "$(printf 'noise\nval_bpb: 0.9979\nmore\n' | "$M" --pattern '^val_bpb:')" "pattern extract"
assert_eq "42"     "$(printf 'coverage is 42 percent\n'        | "$M")"                       "default last number"
assert_eq "-3.5"   "$(printf 'delta -3.5\n'                    | "$M")"                       "negative float"
printf 'no numbers here\n' | "$M" >/dev/null 2>&1; assert_exit 1 $? "no number → exit 1"

assert_done
