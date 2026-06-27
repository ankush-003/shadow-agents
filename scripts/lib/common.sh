#!/usr/bin/env bash
# Shared helpers for Shadow Legion scripts. Source me; do not execute.
: "${SHADOW_HOME:=$HOME/.shadow}"
export SHADOW_HOME

if [ -t 1 ]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_DIM=""; C_RESET=""
fi

shadow_die(){ printf '%s%s%s\n' "$C_RED" "$1" "$C_RESET" >&2; exit 1; }

# json_get <file> <jq_filter> — echoes value, or empty string if file/key missing.
json_get(){
  [ -f "$1" ] || { printf ''; return 0; }
  jq -r "$2 // empty" "$1" 2>/dev/null || printf ''
}
