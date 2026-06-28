#!/usr/bin/env bash
# Shadow Legion experiment monitor. Each stdout line becomes a Claude notification.
# Emits one line per new results.tsv row and per newly-seen run dir.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
STATE="$(mktemp -d "${TMPDIR:-/tmp}/shadow-mon.XXXXXX")"
trap 'rm -rf "$STATE"' EXIT

key(){ printf '%s' "$1" | tr -c 'A-Za-z0-9' '_'; }

scan_once(){
  for tsv in "$ROOT"/.shadow/experiments/*/results.tsv "$ROOT"/.shadow/campaign-*/*/results.tsv; do
    [ -f "$tsv" ] || continue
    id="$(basename "$(dirname "$tsv")")"
    runf="$STATE/run_$(key "$id")"
    if [ ! -f "$runf" ]; then printf '▶ %s started\n' "$id"; : > "$runf"; fi
    cntf="$STATE/rows_$(key "$id")"
    prev=0; [ -f "$cntf" ] && prev="$(cat "$cntf")"
    total="$(grep -cE '^[0-9]' "$tsv" 2>/dev/null || echo 0)"
    if [ "$total" -gt "$prev" ]; then
      grep -E '^[0-9]' "$tsv" | tail -n +"$((prev + 1))" | while IFS="$(printf '\t')" read -r it ts commit metric delta guard status desc; do
        printf '🌑 %s iter %s: metric=%s (Δ%s) [%s] %s\n' "$id" "$it" "$metric" "$delta" "$status" "$desc"
      done
      printf '%s' "$total" > "$cntf"
    fi
  done
}

if [ "${SHADOW_MONITOR_ONCE:-0}" = "1" ]; then scan_once; exit 0; fi
while true; do scan_once; sleep 3; done
