#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
for t in "$DIR"/test_*.sh; do
  [ -e "$t" ] || continue
  printf '\n▶ %s\n' "$(basename "$t")"
  bash "$t" || fail=1
done
if [ "$fail" -eq 0 ]; then printf '\n\033[32m✓ all tests passed\033[0m\n'; else printf '\n\033[31m✗ tests failed\033[0m\n'; exit 1; fi
