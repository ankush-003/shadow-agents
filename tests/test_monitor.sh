#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
M="$DIR/../scripts/monitor-experiments.sh"

root="$(mktemp -d)"
mkdir -p "$root/.shadow/experiments/exp-001"
{
  printf '# metric_direction: lower_is_better\n'
  printf 'iteration\ttimestamp\tcommit\tmetric\tdelta\tguard\tstatus\tdescription\n'
  printf '0\t2026-01-01T00:00:00Z\tabc1234\t3\t0.0\tpass\tbaseline\tinitial\n'
  printf '1\t2026-01-01T00:01:00Z\tdef5678\t2\t-1.0\tpass\tkeep\tremoved TODO a\n'
} > "$root/.shadow/experiments/exp-001/results.tsv"

out="$(CLAUDE_PROJECT_DIR="$root" SHADOW_MONITOR_ONCE=1 bash "$M" 2>&1)"
assert_contains "$out" "exp-001" "emits run id"
assert_contains "$out" "started" "emits new-run line"
assert_contains "$out" "iter 0" "emits baseline row"
assert_contains "$out" "iter 1" "emits second row"
assert_contains "$out" "keep" "emits status"
rm -rf "$root"
assert_done
