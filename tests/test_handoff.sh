#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
H="$DIR/../scripts/handoff.sh"

good="$(mktemp)"; cat > "$good" <<'JSON'
{ "best": {"commit":"abc1234","metric":"0.9931"},
  "hypothesis":"larger batch lowers bpb",
  "next_step":"try batch=64 with lr warmup",
  "learnings":[{"claim":"GeLU regresses bpb","implication":"stop trying activation swaps"}] }
JSON
"$H" validate "$good"; assert_exit 0 $? "valid handoff passes"

bad="$(mktemp)"; cat > "$bad" <<'JSON'
{ "best": {"commit":"abc1234","metric":"0.99"},
  "hypothesis":"x", "next_step":"y",
  "learnings":[{"claim":"tried X, was fine"}] }
JSON
"$H" validate "$bad" 2>/dev/null; assert_exit 1 $? "learning without implication rejected"

"$H" validate /no/file 2>/dev/null; assert_exit 1 $? "missing file rejected"
rm -f "$good" "$bad"
assert_done
