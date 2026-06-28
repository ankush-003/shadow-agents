#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"

cmd="${1:-}"; [ -n "$cmd" ] || shadow_die "usage: kb.sh search <query> [root] | index [root]"
shift

_root(){ printf '%s' "${1:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"; }
_col(){ printf 'sl_%s' "$(basename "$1" | tr -c 'A-Za-z0-9' '_')"; }
_ms(){
  [ -n "${SHADOW_KB_NOMEMSEARCH:-}" ] && { printf ''; return 0; }
  if command -v memsearch >/dev/null 2>&1; then printf 'memsearch'
  elif command -v uvx >/dev/null 2>&1; then printf 'uvx --from memsearch[onnx] memsearch'
  else printf ''; fi
}

case "$cmd" in
  search)
    q="${1:-}"; [ -n "$q" ] || shadow_die "search: query required"
    root="$(_root "${2:-}")"; kbdir="$root/.shadow"
    ms="$(_ms)"
    if [ -n "$ms" ]; then
      out="$($ms search "$q" --collection "$(_col "$root")" --top-k 5 2>/dev/null || true)"
      [ -n "$out" ] && { printf '%s\n' "$out"; exit 0; }
    fi
    [ -d "$kbdir" ] || exit 0
    grep -rinE "$q" "$kbdir" --include='*.md' --include='*.tsv' 2>/dev/null | head -20 || true
    ;;
  index)
    root="$(_root "${1:-}")"; ms="$(_ms)"
    [ -n "$ms" ] || { echo "kb: memsearch unavailable — grep fallback active (no index needed)"; exit 0; }
    [ -d "$root/.shadow" ] || { echo "kb: nothing to index"; exit 0; }
    if $ms index "$root/.shadow" --collection "$(_col "$root")" >/dev/null 2>&1; then
      echo "kb: indexed $root/.shadow"
    else
      echo "kb: index skipped (memsearch error) — grep fallback active"
    fi
    ;;
  *) shadow_die "unknown subcommand: $cmd" ;;
esac
