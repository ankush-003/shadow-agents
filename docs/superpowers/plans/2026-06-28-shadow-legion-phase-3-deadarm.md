# Shadow Legion — Phase 3: Reasoned Dead-Arm Pruning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the bandit genuinely prune dead experiment directions — but only with a *recorded reason* (why it failed, from the experiment's learnings) and after *verification* (a confirmed no-improvement streak, not a one-off), writing each pruned direction to a `graveyard.md` so future shadows don't retry it.

**Architecture:** Additive changes to the deterministic seam `allocate.sh` (each arm gains a `no_improve_streak` and a `dead_reason`; new subcommands `dead-candidates`, `mark-dead`, `dead-report`). A new `graveyard.sh` writes human-readable pruned-direction entries. The orchestrator (`commands/campaign.md`) detects dead candidates after each cycle, derives the reason from the arm's Tusk learnings, optionally confirms, then calls `mark-dead` + appends to `graveyard.md`. Tusk reads `graveyard.md` in its RECALL step to avoid dead approaches. No new external deps. Builds on Phase 2 (now on `main`).

**Tech Stack:** Bash 3.2 (macOS), `jq`. Tests via the existing `tests/run.sh` harness.

## Global Constraints

- **Bash 3.2** (macOS): no associative arrays, no `${var^^}`, no `mapfile`. `jq` for JSON.
- Executable scripts: `#!/usr/bin/env bash` + `set -euo pipefail`; sourced libs do not; tests use `set -uo pipefail`.
- **Additive only**: existing `allocate.sh` subcommands/contracts and existing tests must keep passing. New arm fields must not break existing jq-path assertions.
- **Reasoned + verified pruning**: an arm becomes dead ONLY via `mark-dead <armid> <reason>` with a non-empty reason; the orchestrator calls it after a confirmed `no_improve_streak >= dead_k` (default 2). Never auto-kill inside `update`.
- `dead_k` default **2** consecutive non-improving attempts before an arm is a *candidate* (not yet dead).
- Determinism preserved: `SHADOW_ALLOC_GREEDY=1` still forces ε=0. `next-arm`/`status` already skip `dead==true`.
- No placeholders.

---

## File Structure

```
scripts/
├── allocate.sh        # MODIFIED — no_improve_streak + dead_reason; dead-candidates/mark-dead/dead-report
└── graveyard.sh       # NEW — append a pruned-direction entry to graveyard.md
agents/tusk.md         # MODIFIED — RECALL step reads graveyard.md (avoid dead approaches)
commands/campaign.md   # MODIFIED — detect dead-candidates → reason → mark-dead + graveyard append
tests/
├── test_allocate.sh   # MODIFIED — streak / dead-candidates / mark-dead / next-arm-skips-dead
├── test_graveyard.sh  # NEW
└── test_manifests.sh  # MODIFIED — campaign/tusk graveyard wiring checks
```

---

## Task 1: `allocate.sh` — reasoned dead-arm support

**Files:**
- Modify: `scripts/allocate.sh`
- Modify: `tests/test_allocate.sh`

**Interfaces:**
- `add-arm` also initializes `no_improve_streak:0`, `dead_reason:null`.
- `update <sf> <armid> <metric> <delta> <status>` additionally: if this update improved `best` (direction-aware), reset that arm's `no_improve_streak` to 0; else increment it.
- New `dead-candidates <sf> [dead_k]` (default 2) → echoes arm ids (one per line) that are `dead==false` AND `no_improve_streak >= dead_k`.
- New `mark-dead <sf> <armid> <reason>` → sets that arm `dead:true` and `dead_reason:<reason>` (reason must be non-empty; error if empty).
- New `dead-report <sf>` → echoes `armid<TAB>desc<TAB>dead_reason` for each dead arm (empty output if none).
- Existing `next-arm`/`status` already filter `dead==false`; no change needed there.

- [ ] **Step 1: Add failing tests to `tests/test_allocate.sh`** (before the final `assert_done`)

```bash
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
```

- [ ] **Step 2: Run tests to verify the new cases FAIL**

Run: `bash tests/test_allocate.sh`
Expected: FAIL on the new dead-arm cases (subcommands/fields not present); existing cases still pass.

- [ ] **Step 3: Modify `scripts/allocate.sh`**

3a. In `add-arm`, extend the arm object:
```bash
jq --arg id "$id" --arg d "$desc" \
  '.arms += [{id:$id, desc:$d, attempts:0, mean_delta:0, best:null, last_improved:-1, dead:false, no_improve_streak:0, dead_reason:null}]' \
  "$sf" > "$tmp" && mv "$tmp" "$sf"
```

3b. In `update`, after the existing mean/best logic, maintain the streak. Use the `--arg dir` form already present and add streak handling in the same `map`:
```bash
dir="$(jq -r '.direction' "$sf")"
jq --arg id "$id" --argjson m "$metric" --argjson d "$delta" --arg dir "$dir" '
  .cycle as $c
  | .arms |= map(
      if .id==$id then
        .attempts += 1
        | .mean_delta = ((.mean_delta * (.attempts - 1) + $d) / .attempts)
        | (if (.best==null) or ($dir=="lower_is_better" and $m < .best) or ($dir=="higher_is_better" and $m > .best)
           then .best=$m | .last_improved=$c | .no_improve_streak=0
           else .no_improve_streak=(.no_improve_streak + 1) end)
      else . end)
  | .cycle += 1' "$sf" > "$sf.tmp" && mv "$sf.tmp" "$sf"
```
(Note: the first `update` on an arm sets `best` from null → counts as an improvement → streak 0. The test accounts for this.)

3c. Add new subcommands to the `case`:
```bash
  dead-candidates)
    sf="$1"; k="${2:-2}"
    jq -r --argjson k "$k" '.arms[] | select(.dead==false and .no_improve_streak >= $k) | .id' "$sf"
    ;;
  mark-dead)
    sf="$1"; id="$2"; reason="${3:-}"
    [ -n "$reason" ] || { echo "mark-dead: reason required" >&2; exit 1; }
    jq --arg id "$id" --arg r "$reason" \
      '.arms |= map(if .id==$id then .dead=true | .dead_reason=$r else . end)' \
      "$sf" > "$sf.tmp" && mv "$sf.tmp" "$sf"
    ;;
  dead-report)
    sf="$1"
    jq -r '.arms[] | select(.dead==true) | [.id, .desc, (.dead_reason // "")] | @tsv' "$sf"
    ;;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_allocate.sh` then `bash tests/run.sh`
Expected: PASS — all old + new allocate cases; full suite green.

- [ ] **Step 5: Commit**

```bash
git add scripts/allocate.sh tests/test_allocate.sh
git commit -m "feat: reasoned dead-arm pruning in allocate.sh (streak + mark-dead + dead-report)"
```

---

## Task 2: `graveyard.sh` — record pruned directions

**Files:**
- Create: `scripts/graveyard.sh`
- Test: `tests/test_graveyard.sh`

**Interfaces:**
- `graveyard.sh append <file> <armid> <desc> <reason>` — ensures `<file>` exists with a `# Graveyard — dead directions (do not retry)` header (once), then appends a markdown entry: `## <armid>: <desc>` followed by `- reason: <reason>` and a UTC timestamp line. Creates parent dir if needed.

- [ ] **Step 1: Write the failing test `tests/test_graveyard.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
G="$DIR/../scripts/graveyard.sh"

gv="$(mktemp -d)/graveyard.md"
"$G" append "$gv" a1 "delete TODO lines" "every variant matched baseline; no reduction"
"$G" append "$gv" a2 "rewrite as DONE" "regressed metric on 2/2 tries"
body="$(cat "$gv")"
assert_contains "$body" "# Graveyard" "has header"
assert_contains "$body" "## a1: delete TODO lines" "entry a1"
assert_contains "$body" "no reduction" "a1 reason"
assert_contains "$body" "## a2: rewrite as DONE" "entry a2"
# header appears exactly once
assert_eq "1" "$(grep -c '^# Graveyard' "$gv")" "header written once"
rm -rf "$(dirname "$gv")"
assert_done
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_graveyard.sh`
Expected: FAIL — script missing.

- [ ] **Step 3: Write `scripts/graveyard.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"
[ "$cmd" = "append" ] || { echo "usage: graveyard.sh append <file> <armid> <desc> <reason>" >&2; exit 1; }
file="$2"; arm="$3"; desc="$4"; reason="$5"
mkdir -p "$(dirname "$file")"
[ -f "$file" ] || printf '# Graveyard — dead directions (do not retry)\n\n' > "$file"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
  printf '## %s: %s\n' "$arm" "$desc"
  printf -- '- reason: %s\n' "$reason"
  printf -- '- pruned: %s\n\n' "$ts"
} >> "$file"
```

- [ ] **Step 4: Run tests to verify pass**

Run: `bash tests/test_graveyard.sh` then `bash tests/run.sh`
Expected: PASS. `chmod +x scripts/graveyard.sh`.

- [ ] **Step 5: Commit**

```bash
git add scripts/graveyard.sh tests/test_graveyard.sh
git commit -m "feat: add graveyard.sh to record pruned directions with reasons"
```

---

## Task 3: Wire reasoned pruning into `/campaign` and Tusk RECALL

**Files:**
- Modify: `commands/campaign.md`
- Modify: `agents/tusk.md`
- Modify: `tests/test_manifests.sh`

**Interfaces:**
- Consumes: `allocate.sh dead-candidates/mark-dead/dead-report`, `graveyard.sh append`, Tusk's per-arm learnings.
- Produces: campaign detects dead candidates each cycle, derives the *reason* from that arm's Tusk report/handoff learnings (the why), confirms the streak, then `mark-dead` + `graveyard.sh append`; the final report lists pruned directions with reasons. Tusk's RECALL step reads `graveyard.md` and avoids those approaches.

- [ ] **Step 1: Append wiring checks to `tests/test_manifests.sh`** (before the final `assert_done`)

```bash
# --- Phase 3: reasoned pruning wiring ---
cc="$ROOT/commands/campaign.md"; ccb="$(cat "$cc")"
assert_contains "$ccb" "dead-candidates" "campaign checks dead-candidates"
assert_contains "$ccb" "mark-dead" "campaign marks dead with reason"
assert_contains "$ccb" "graveyard" "campaign records graveyard"
tkb="$(cat "$ROOT/agents/tusk.md")"
assert_contains "$tkb" "graveyard" "tusk RECALL reads graveyard"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_manifests.sh`
Expected: FAIL — campaign/tusk don't mention graveyard/dead yet.

- [ ] **Step 3: Edit `commands/campaign.md`** — add a pruning step inside the campaign loop (after folding results via `allocate.sh update`, before looping). Insert this section:

````markdown
## 4b. Prune dead directions (reasoned + verified)
After updating arms for this cycle, check for dead candidates:
1. `cands=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/allocate.sh dead-candidates <state> 2)` — arms with ≥2 consecutive non-improving attempts.
2. For EACH candidate arm, derive the REASON it failed from that arm's Tusk reports/handoff learnings this campaign (e.g. "every variant regressed the metric because X"). Do not invent a reason — quote the shadow's own learning. If you cannot find a concrete reason, do NOT kill the arm yet (give it one more cycle).
3. With a concrete reason in hand, prune it:
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/allocate.sh mark-dead <state> <armid> "<reason>"`
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/graveyard.sh append <campaign>/graveyard.md <armid> "<desc>" "<reason>"`
A dead arm is skipped by `next-arm` and `status` automatically. Never kill an arm without a recorded reason.
````
Also extend the final report (§5) to include `allocate.sh dead-report <state>` output — the pruned directions and why.

- [ ] **Step 4: Edit `agents/tusk.md`** — add a RECALL note in the protocol (e.g. as part of step 2 "Resume?"): 
```
- RECALL: if `OutDir/../graveyard.md` (the campaign graveyard) exists, read it first and do NOT repeat any approach already recorded there as dead — pick a different angle.
```

- [ ] **Step 5: Run tests**

Run: `bash tests/test_manifests.sh` then `bash tests/run.sh`
Expected: PASS — wiring checks green; full suite green. Confirm exactly one `assert_done` as the last line.

- [ ] **Step 6: Commit**

```bash
git add commands/campaign.md agents/tusk.md tests/test_manifests.sh
git commit -m "feat: wire reasoned dead-arm pruning + graveyard recall into campaign/tusk"
```

---

## Task 4: Suite + load + dead-arm flow dry-run

**Files:** none (verification).

- [ ] **Step 1: Full suite** — `bash tests/run.sh`. Expected: all green (incl. test_graveyard.sh, new allocate cases).

- [ ] **Step 2: Lint (if available)** — `command -v shellcheck >/dev/null && shellcheck scripts/*.sh tests/*.sh || echo "shellcheck not installed — skipping"`.

- [ ] **Step 3: Dead-arm flow dry-run (no agents — proves the seam):**
```bash
sf="$(mktemp)"; A=scripts/allocate.sh; G=scripts/graveyard.sh; gv="$(mktemp -d)/graveyard.md"
"$A" init "$sf" lower_is_better 20 3
"$A" add-arm "$sf" a1 "dead end"; "$A" add-arm "$sf" a2 "winner"
"$A" update "$sf" a1 3 0 discard; "$A" update "$sf" a1 3 0 discard   # a1 stalls
echo "candidates@2: $("$A" dead-candidates "$sf" 2)"                  # expect a1
"$A" mark-dead "$sf" a1 "all variants matched baseline 3 (no reduction)"
"$G" append "$gv" a1 "dead end" "all variants matched baseline 3 (no reduction)"
echo "next after prune: $("$A" next-arm "$sf")"                       # expect a2
echo "dead-report:"; "$A" dead-report "$sf"
echo "graveyard:"; cat "$gv"
rm -f "$sf"; rm -rf "$(dirname "$gv")"
```
Expected: `candidates@2: a1`, `next after prune: a2`, dead-report shows a1 + reason, graveyard.md has the entry.

- [ ] **Step 4: Plugin load** — `claude --plugin-dir "$(pwd)" --model haiku -p "Reply with exactly: LOADED"`. Expected `LOADED`. If unavailable, DEFERRED.

- [ ] **Step 5: Tag** — `git tag phase-3-deadarm`.

---

## Self-Review

**Spec coverage:** reasoned dead-arm (streak + `mark-dead`-requires-reason) → Task 1; recorded why (`graveyard.sh` + `dead_reason`) → Tasks 1–2; verification before kill (orchestrator derives a concrete reason from Tusk learnings, else waits) → Task 3; future shadows avoid dead approaches (Tusk RECALL reads graveyard) → Task 3; deterministic flow preserved (no auto-kill in `update`; pruning is an explicit orchestrator step) → Tasks 1, 3. Additive — existing tests/contracts untouched.

**Placeholder scan:** complete code in every shell step; prose steps for the prompt files name exact commands. "dead"/"graveyard" strings are domain terms, not placeholders.

**Interface consistency:** `dead-candidates`/`mark-dead`/`dead-report`/`graveyard.sh append` signatures match between Task 1/2 definitions, Task 3 wiring, and Task 4 dry-run; arm fields `no_improve_streak`/`dead_reason` added in `add-arm` and read by the new subcommands.

## Notes for the executor
- Additive changes only — run the FULL suite after Task 1 to confirm no Phase-1/2 regressions.
- Never auto-kill an arm inside `update`; pruning is an explicit, reasoned orchestrator decision.
- Insert new test_manifests checks before the single trailing `assert_done`.
- Don't push or open PRs during implementation.
