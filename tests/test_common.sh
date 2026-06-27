#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
. "$DIR/../scripts/lib/common.sh"

# SHADOW_HOME default
assert_contains "$SHADOW_HOME" ".shadow" "SHADOW_HOME defaults under home"

# json_get reads a value
tmp="$(mktemp)"; printf '{"rank":"C","level":7}' > "$tmp"
assert_eq "C" "$(json_get "$tmp" '.rank')" "json_get reads .rank"
assert_eq "7" "$(json_get "$tmp" '.level')" "json_get reads .level"
rm -f "$tmp"

# json_get on missing file → empty, no crash
assert_eq "" "$(json_get /no/such/file '.rank')" "json_get missing file is empty"

assert_done
