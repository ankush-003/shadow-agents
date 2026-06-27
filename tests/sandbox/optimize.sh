#!/usr/bin/env bash
# Smoke metric: counts TODO markers in tests/sandbox/work.txt (lower_is_better).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
f="$DIR/work.txt"
[ -f "$f" ] || printf 'TODO a\nTODO b\nTODO c\nkeep me\n' > "$f"
grep -c 'TODO' "$f" || true
