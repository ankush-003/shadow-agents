#!/usr/bin/env bash

check_tool(){ # display cmd [alt]
  display="$1"; cmd="$2"; alt="${3:-}"
  if command -v "$cmd" >/dev/null 2>&1 || { [ -n "$alt" ] && command -v "$alt" >/dev/null 2>&1; }; then
    printf '[ok] %s\n' "$display"; return 0
  fi
  printf '[MISSING] %s\n' "$display"; return 1
}

# When sourced for tests, stop here.
[ -n "${SHADOW_PREFLIGHT_LIB:-}" ] && return 0 2>/dev/null || true

set -euo pipefail

rc=0
check_tool git git       || rc=1
check_tool jq jq         || rc=1
check_tool claude claude || rc=1
check_tool "memsearch (or uvx)" memsearch uvx || rc=1
# gh is OPTIONAL — integration is proposal-only; gh is not needed.
if command -v gh >/dev/null 2>&1; then echo "[opt] gh present"; else echo "[opt] gh absent — proposal-only integration"; fi
if [ "$rc" -ne 0 ]; then
  echo "Preflight failed. Install missing tools:" >&2
  echo "  memsearch:  uv tool install 'memsearch[onnx]'  (or: pipx install 'memsearch[onnx]')" >&2
  exit 1
fi
echo "All systems ready. ARISE."
