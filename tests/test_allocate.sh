#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
A="$DIR/../scripts/allocate.sh"
export SHADOW_ALLOC_GREEDY=1   # deterministic: pure exploit, no epsilon randomness

sf="$(mktemp)"
"$A" init "$sf" lower_is_better 50 3
assert_eq "lower_is_better" "$(jq -r '.direction' "$sf")" "init direction"
assert_eq "0" "$(jq -r '.cycle' "$sf")" "init cycle 0"

"$A" add-arm "$sf" a1 "remove TODO lines"
"$A" add-arm "$sf" a2 "rewrite TODOs"
assert_eq "2" "$(jq -r '.arms|length' "$sf")" "two arms"

# untried arms first, in order
assert_eq "a1" "$("$A" next-arm "$sf")" "next-arm picks first untried"

# a1 improves (delta -1, metric 2), a2 tried but worse (delta 0, metric 3)
"$A" update "$sf" a1 2 -1 keep
"$A" update "$sf" a2 3 0 discard
assert_eq "2" "$(jq -r '.cycle' "$sf")" "cycle advanced to 2"
assert_eq "2" "$(jq -r '.arms[]|select(.id=="a1").best' "$sf")" "a1 best metric 2"

# both tried now -> greedy exploit picks better mean_delta (a1: -1 < a2: 0, lower delta is better improvement)
assert_eq "a1" "$("$A" next-arm "$sf")" "greedy exploits best arm a1"

# status: still running (cycle 2 < ceiling, a1 improved recently)
assert_eq "RUNNING" "$("$A" status "$sf")" "status running"
# target met -> converged (best=2, target 2, lower_is_better)
assert_eq "CONVERGED" "$("$A" status "$sf" 2)" "status converged at target"

# ceiling
sf2="$(mktemp)"; "$A" init "$sf2" higher_is_better 1 3; "$A" add-arm "$sf2" b1 x
"$A" update "$sf2" b1 5 5 keep   # cycle -> 1 == ceiling
assert_eq "CEILING" "$("$A" status "$sf2")" "status ceiling"

rm -f "$sf" "$sf2"

# higher_is_better: greedy exploit must pick the HIGHEST mean_delta
sf3="$(mktemp)"
"$A" init "$sf3" higher_is_better 50 3
"$A" add-arm "$sf3" h1 "approach one"
"$A" add-arm "$sf3" h2 "approach two"
"$A" next-arm "$sf3" >/dev/null     # consume untried h1
"$A" update "$sf3" h1 5 1 keep      # h1 mean_delta +1
"$A" update "$sf3" h2 9 5 keep      # h2 mean_delta +5 (better for higher_is_better)
assert_eq "h2" "$("$A" next-arm "$sf3")" "greedy higher_is_better picks highest mean_delta"
rm -f "$sf3"

# --- Phase 3: reasoned dead-arm pruning ---
sfd="$(mktemp)"
"$A" init "$sfd" lower_is_better 50 3
"$A" add-arm "$sfd" d1 "dead-end approach"
"$A" add-arm "$sfd" d2 "good approach"
assert_eq "0" "$(jq -r '.arms[]|select(.id=="d1").no_improve_streak' "$sfd")" "streak starts 0"

# d1 keeps not improving -> streak grows; d2 improves -> streak resets/stays 0
"$A" update "$sfd" d1 3 0 discard     # no improvement (best stays null->set to 3 first time actually)
"$A" update "$sfd" d1 3 0 discard     # still 3, no improvement
sd1="$(jq -r '.arms[]|select(.id=="d1").no_improve_streak' "$sfd")"
assert_eq "1" "$sd1" "d1 streak=1 after one non-improving (first update set baseline best)"

# dead-candidates at threshold 1 includes d1, not d2
cand="$("$A" dead-candidates "$sfd" 1)"
assert_contains "$cand" "d1" "d1 is a dead candidate at k=1"
case "$cand" in *d2*) echo "  FAIL d2 should not be candidate" >&2; ASSERT_FAILS=$((ASSERT_FAILS+1));; *) _pass "d2 not a candidate";; esac

# mark-dead requires a reason and sets dead + reason
"$A" mark-dead "$sfd" d1 "every variant worsened or matched baseline 3"
assert_eq "true" "$(jq -r '.arms[]|select(.id=="d1").dead' "$sfd")" "d1 marked dead"
assert_contains "$("$A" dead-report "$sfd")" "worsened" "dead-report shows reason"

# mark-dead with empty reason errors
"$A" mark-dead "$sfd" d2 "" 2>/dev/null; assert_exit 1 $? "mark-dead rejects empty reason"

# next-arm now skips the dead d1, returns live d2 (untried)
assert_eq "d2" "$("$A" next-arm "$sfd")" "next-arm skips dead arm"
rm -f "$sfd"

assert_done
