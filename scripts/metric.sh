#!/usr/bin/env bash
set -euo pipefail
pattern=""
if [ "${1:-}" = "--pattern" ]; then pattern="${2:-}"; fi
num_re='-\{0,1\}[0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}'

input="$(cat)"
if [ -n "$pattern" ]; then
  line="$(printf '%s\n' "$input" | grep -E "$pattern" | head -1 || true)"
  val="$(printf '%s' "$line" | grep -o -e "$num_re" | head -1 || true)"
else
  val="$(printf '%s' "$input" | grep -o -e "$num_re" | tail -1 || true)"
fi
[ -n "$val" ] || exit 1
printf '%s\n' "$val"
