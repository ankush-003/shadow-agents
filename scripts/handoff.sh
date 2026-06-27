#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"

cmd="${1:-}"; file="${2:-}"
[ "$cmd" = "validate" ] || shadow_die "usage: handoff.sh validate <file.json>"
[ -f "$file" ] || { echo "invalid: file not found" >&2; exit 1; }

err="$(jq -r '
  def bad(m): m;
  if (.best|type)!="object" then bad("best missing")
  elif (.best.commit|type)!="string" or (.best.commit|length)==0 or (.best.metric==null) then bad("best.commit/metric missing")
  elif (.hypothesis|type)!="string" or (.hypothesis|length)==0 then bad("hypothesis empty")
  elif (.next_step|type)!="string" or (.next_step|length)==0 then bad("next_step empty")
  elif (.learnings|type)!="array" then bad("learnings not array")
  elif ([.learnings[] | select((.claim|type)!="string" or (.claim|length)==0 or (.implication|type)!="string" or (.implication|length)==0)] | length) > 0
    then bad("a learning lacks non-empty claim+implication")
  else "" end
' "$file" 2>/dev/null || echo "not valid json")"

if [ -n "$err" ]; then echo "invalid: $err" >&2; exit 1; fi
exit 0
