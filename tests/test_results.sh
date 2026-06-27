#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
. "$DIR/../scripts/results.sh"

out="$(mktemp -d)"
results_init "$out" "lower_is_better"
hdr="$(sed -n '1p' "$out/results.tsv")"
assert_contains "$hdr" "metric_direction: lower_is_better" "direction recorded"
cols="$(sed -n '2p' "$out/results.tsv")"
assert_contains "$cols" "iteration	timestamp	commit	metric" "header columns"

results_append "$out" 0 abc1234 0.997900 0.0 pass keep baseline
row="$(sed -n '3p' "$out/results.tsv")"
assert_contains "$row" "abc1234" "row has commit"
assert_contains "$row" "baseline" "row has description"
assert_contains "$row" "keep" "row has status"
rm -rf "$out"
assert_done
