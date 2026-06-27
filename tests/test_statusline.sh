#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
SL="$DIR/../statusline/legion.sh"

export SHADOW_HOME="$(mktemp -d)"
printf '{"level":8,"rank":"C","xp":900}' > "$SHADOW_HOME/hunter.json"
in='{"model":"claude-sonnet-4-6","context":{"percent_used":12,"total_tokens":24000,"max_tokens":200000}}'
out="$(printf '%s' "$in" | "$SL")"
assert_contains "$out" "Lv.8"   "shows level"
assert_contains "$out" "C-Rank" "shows rank"
assert_contains "$out" "12%"    "shows context percent"
assert_contains "$out" "claude-sonnet-4-6" "shows model"

# defaults when no hunter.json
rm -f "$SHADOW_HOME/hunter.json"
out2="$(printf '%s' "$in" | "$SL")"
assert_contains "$out2" "Lv.1"   "defaults to Lv.1"
assert_contains "$out2" "E-Rank" "defaults to E rank"
rm -rf "$SHADOW_HOME"
assert_done
