#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"
[ "$cmd" = "append" ] || { echo "usage: graveyard.sh append <file> <armid> <desc> <reason>" >&2; exit 1; }
file="$2"; arm="$3"; desc="$4"; reason="$5"
mkdir -p "$(dirname "$file")"
[ -f "$file" ] || printf '# Graveyard — dead directions (do not retry)\n\n' > "$file"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
  printf '## %s: %s\n' "$arm" "$desc"
  printf -- '- reason: %s\n' "$reason"
  printf -- '- pruned: %s\n\n' "$ts"
} >> "$file"
