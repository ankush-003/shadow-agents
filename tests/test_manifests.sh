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
# --- Monarch skill ---
sk="$ROOT/skills/monarch/SKILL.md"
assert_eq "1" "$([ -f "$sk" ] && echo 1 || echo 0)" "monarch SKILL.md exists"
assert_contains "$(sed -n '1,6p' "$sk")" "name: monarch" "monarch frontmatter name"
assert_contains "$(sed -n '1,6p' "$sk")" "description:" "monarch frontmatter description"
assert_eq "1" "$([ -s "$ROOT/output-styles/monarch.md" ] && echo 1 || echo 0)" "output style non-empty"
# --- Tusk agent ---
tk="$ROOT/agents/tusk.md"
fm="$(sed -n '1,12p' "$tk" 2>/dev/null)"
assert_contains "$fm" "name: tusk" "tusk name"
assert_contains "$fm" "isolation: worktree" "tusk isolated in worktree"
assert_contains "$fm" "model: sonnet" "tusk runs sonnet"
assert_contains "$fm" "maxTurns:" "tusk has maxTurns cap"
assert_done
