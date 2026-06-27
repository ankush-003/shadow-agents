#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
ROOT="$DIR/.."

jq empty "$ROOT/.claude-plugin/plugin.json"; assert_exit 0 $? "plugin.json valid json"
assert_eq "shadow-legion" "$(jq -r '.name' "$ROOT/.claude-plugin/plugin.json")" "plugin name"
assert_eq "./statusline/legion.sh" "$(jq -r '.statusline' "$ROOT/.claude-plugin/plugin.json")" "statusline declared"

jq empty "$ROOT/.claude-plugin/marketplace.json"; assert_exit 0 $? "marketplace.json valid json"
assert_eq "shadow-legion" "$(jq -r '.plugins[0].name' "$ROOT/.claude-plugin/marketplace.json")" "marketplace plugin name"
assert_eq "." "$(jq -r '.plugins[0].source' "$ROOT/.claude-plugin/marketplace.json")" "marketplace source is repo root"
assert_done
