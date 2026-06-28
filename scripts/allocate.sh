#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"

cmd="${1:-}"; [ -n "$cmd" ] || shadow_die "usage: allocate.sh init|add-arm|next-arm|update|status ..."
shift

case "$cmd" in
  init)
    sf="$1"; direction="$2"; ceiling="${3:-50}"; plateau="${4:-3}"; mkdir -p "$(dirname "$sf")"
    jq -n --arg dir "$direction" --argjson ceil "$ceiling" --argjson plat "$plateau" \
      '{direction:$dir, cycle:0, ceiling:$ceil, plateau_k:$plat, arms:[]}' > "$sf"
    ;;
  add-arm)
    sf="$1"; id="$2"; desc="$3"; tmp="$sf.tmp"
    jq --arg id "$id" --arg d "$desc" \
      '.arms += [{id:$id, desc:$d, attempts:0, mean_delta:0, best:null, last_improved:-1, dead:false}]' \
      "$sf" > "$tmp" && mv "$tmp" "$sf"
    ;;
  next-arm)
    sf="$1"
    cycle="$(jq -r '.cycle' "$sf")"; ceiling="$(jq -r '.ceiling' "$sf")"
    if [ "$cycle" -ge "$ceiling" ]; then echo STOP; exit 0; fi
    live="$(jq -r '[.arms[]|select(.dead==false)]|length' "$sf")"
    if [ "$live" -eq 0 ]; then echo STOP; exit 0; fi
    untried="$(jq -r '[.arms[]|select(.dead==false and .attempts==0)][0].id // empty' "$sf")"
    if [ -n "$untried" ]; then echo "$untried"; exit 0; fi
    if [ "${SHADOW_ALLOC_GREEDY:-0}" = "1" ]; then eps=0
    else eps=$(( 50 - (cycle * 50 / ceiling) )); [ "$eps" -lt 5 ] && eps=5; fi
    r=$(( RANDOM % 100 ))
    if [ "$r" -lt "$eps" ]; then
      idx=$(( RANDOM % live ))
      jq -r --argjson i "$idx" '[.arms[]|select(.dead==false)]|.[$i].id' "$sf"
    else
      jq -r '[.arms[]|select(.dead==false)]|sort_by(.mean_delta)|.[0].id' "$sf"
    fi
    ;;
  update)
    sf="$1"; id="$2"; metric="$3"; delta="$4"; status="$5"; tmp="$sf.tmp"
    dir="$(jq -r '.direction' "$sf")"
    jq --arg id "$id" --argjson m "$metric" --argjson d "$delta" --arg dir "$dir" '
      .cycle as $c
      | .arms |= map(if .id==$id then
          .attempts += 1
          | .mean_delta = ((.mean_delta * (.attempts - 1) + $d) / .attempts)
          | (if (.best==null) or ($dir=="lower_is_better" and $m < .best) or ($dir=="higher_is_better" and $m > .best)
             then .best=$m | .last_improved=$c else . end)
        else . end)
      | .cycle += 1' "$sf" > "$tmp" && mv "$tmp" "$sf"
    ;;
  status)
    sf="$1"; target="${2:-}"
    jq -r --arg target "$target" '
      def best:
        ([.arms[].best] | map(select(.!=null))) as $b
        | if ($b|length)==0 then null
          elif .direction=="lower_is_better" then ($b|min) else ($b|max) end;
      .cycle as $c | .ceiling as $ceil | .plateau_k as $pk | (best) as $best
      | if $c >= $ceil then "CEILING"
        elif ($target != "" and $best != null and
              ((.direction=="lower_is_better" and $best <= ($target|tonumber)) or
               (.direction=="higher_is_better" and $best >= ($target|tonumber)))) then "CONVERGED"
        elif ([.arms[]|select(.dead==false and (.attempts==0 or ($c - .last_improved) < $pk))]|length)==0 then "PLATEAU"
        else "RUNNING" end
    ' "$sf"
    ;;
  *) shadow_die "unknown subcommand: $cmd" ;;
esac
