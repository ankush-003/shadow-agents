#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../scripts/lib/common.sh"

payload="$(cat)"
model="$(printf '%s' "$payload" | jq -r '.model // "?"' 2>/dev/null || echo '?')"
pct="$(printf '%s' "$payload" | jq -r '.context.percent_used // 0' 2>/dev/null || echo 0)"

hf="$SHADOW_HOME/hunter.json"
level="$(json_get "$hf" '.level')"; level="${level:-1}"
rank="$(json_get "$hf" '.rank')";  rank="${rank:-E}"

printf '\033[35m「Lv.%s」\033[0m%s-Rank \033[2mctx %s%% │ %s\033[0m\n' "$level" "$rank" "$pct" "$model"
