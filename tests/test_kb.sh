#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
K="$DIR/../scripts/kb.sh"

root="$(mktemp -d)"; mkdir -p "$root/.shadow/experiments/exp-1"
printf '## Iteration 1\nTried GeLU activation -> regressed bpb. Discarded.\n' \
  > "$root/.shadow/experiments/exp-1/exp-notes.md"

# grep fallback (forced) finds a known term + its context line
out="$(SHADOW_KB_NOMEMSEARCH=1 "$K" search "GeLU" "$root")"
assert_contains "$out" "GeLU" "kb search finds known term"
assert_contains "$out" "regressed" "kb search returns context line"

# miss returns empty
miss="$(SHADOW_KB_NOMEMSEARCH=1 "$K" search "quantummonad" "$root")"
assert_eq "" "$miss" "kb search empty on miss"

# search on a root with no .shadow is safe/empty
empty_root="$(mktemp -d)"
none="$(SHADOW_KB_NOMEMSEARCH=1 "$K" search "anything" "$empty_root")"
assert_eq "" "$none" "kb search empty when no .shadow"

# index degrades gracefully without memsearch
idx="$(SHADOW_KB_NOMEMSEARCH=1 "$K" index "$root")"
assert_contains "$idx" "fallback" "index degrades gracefully without memsearch"

rm -rf "$root" "$empty_root"
assert_done
