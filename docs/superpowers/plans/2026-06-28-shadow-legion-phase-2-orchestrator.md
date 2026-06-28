# Shadow Legion — Phase 2: Plugin-owned Orchestrator + Monitors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a plugin-owned `/campaign` orchestrator that runs MANY experiments across candidate directions — dispatching Tusk subagents in parallel (each in its own git worktree), allocating effort with a deterministic bandit seam (`allocate.sh`), and surfacing live progress through a plugin monitor — converging on the best result and reporting learnings. No dependency on the Workflow tool.

**Architecture:** The orchestration *flow* lives in a deterministic shell seam (`allocate.sh`, operating on `orchestrator-state.json`) so it is reproducible and inspectable, not improvised by the LLM. The Monarch (`commands/campaign.md`) is thin glue: it asks `allocate.sh` what to try next, dispatches Tusk subagents (the existing executor, now creating its own worktree per the validated finding), folds each result back via `allocate.sh update`, and checks `allocate.sh status` for stop conditions. A background monitor (`monitor-experiments.sh` via `monitors/monitors.json`) streams each new results row as a notification, giving live visibility without `/workflows`. Builds directly on Phase 0+1 (scripts, tusk, /experiment, test harness).

**Tech Stack:** Bash 3.2 (macOS), `jq`, git worktrees, Claude Code plugin format. Tests are the existing plain-bash harness (`tests/run.sh`).

## Global Constraints

- **Bash 3.2 compatible** (macOS): no `declare -A`, no `${var^^}`, no `mapfile`. Use `$RANDOM`, `jq`.
- **`jq` is the JSON tool.** Executable scripts start `#!/usr/bin/env bash` + `set -euo pipefail`; sourced libs do NOT set those; test files use `set -uo pipefail`.
- **`${CLAUDE_PLUGIN_ROOT}`** at runtime; scripts resolve their own dir via `BASH_SOURCE` so tests can call them directly.
- **Project state** under `<git-root>/.shadow/`; campaign state under `.shadow/campaign-<ts>/`. Global role state under `${SHADOW_HOME:-$HOME/.shadow}` (unchanged from Phase 1).
- **Worktrees: each shadow runs `git worktree add` itself** (PLAN §7). Do NOT use native `isolation: worktree` — it breaks when the session isn't a recognized git repo.
- **Safety (PLAN §9):** safety-screen every Verify/Guard via exit code (`2>&1`, non-zero = refuse). NEVER push/merge/deploy. Integration is PR-only, human-reviewed.
- **Determinism:** all allocation/stop decisions come from `allocate.sh`, never from the LLM's judgement. `SHADOW_ALLOC_GREEDY=1` forces pure-exploit (no ε randomness) for reproducible runs and tests.
- **Monitors** require Claude Code ≥ v2.1.105. **No placeholders** — every shipped file is complete.
- **Command namespacing:** the command is invoked `/shadow-legion:campaign` (document in reports).

---

## File Structure

```
scripts/
├── allocate.sh                 # NEW — deterministic bandit/ledger seam over orchestrator-state.json
└── monitor-experiments.sh      # NEW — background monitor: emits new results rows + new runs
monitors/
└── monitors.json               # NEW — declares the experiment monitor (auto-discovered)
agents/
└── tusk.md                     # MODIFIED — create own worktree (no native isolation); accept Approach
commands/
└── campaign.md                 # NEW — the Monarch orchestrator protocol
tests/
├── test_allocate.sh            # NEW
├── test_monitor.sh             # NEW
└── test_manifests.sh           # MODIFIED — tusk worktree check; campaign command checks; monitor checks
```

Responsibilities: `allocate.sh` owns ALL flow decisions (which arm next, when to stop) as pure functions over a JSON ledger. `campaign.md` owns dispatch/glue only. `monitor-experiments.sh` owns visibility. `tusk.md` owns one experiment in its own worktree.

---

## Task 1: `allocate.sh` — deterministic bandit/ledger seam

**Files:**
- Create: `scripts/allocate.sh`
- Test: `tests/test_allocate.sh`

**Interfaces:**
- Produces an executable with subcommands over a state file (`orchestrator-state.json`):
  - `init <sf> <direction> <ceiling> <plateau_k>` — write base ledger `{direction, cycle:0, ceiling, plateau_k, arms:[]}`.
  - `add-arm <sf> <id> <desc>` — append `{id, desc, attempts:0, mean_delta:0, best:null, last_improved:-1, dead:false}`.
  - `next-arm <sf>` — echo the arm id to try next, or `STOP`. Order: (1) `STOP` if `cycle>=ceiling` or no live arms; (2) first live untried arm (attempts==0); (3) else ε-greedy between best `mean_delta` (exploit) and a random live arm (explore), ε annealed by cycle, floor 5%. `SHADOW_ALLOC_GREEDY=1` → ε=0 (pure exploit, deterministic).
  - `update <sf> <armid> <metric> <delta> <status>` — increment that arm's attempts, update running `mean_delta`, update `best` (direction-aware) and `last_improved` on improvement, then `cycle += 1`.
  - `status <sf> [target]` — echo `CEILING` | `CONVERGED` (target met, direction-aware) | `PLATEAU` (no live arm is untried or recently-improved within `plateau_k`) | `RUNNING`.

- [ ] **Step 1: Write the failing test `tests/test_allocate.sh`**

```bash
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
assert_done
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_allocate.sh`
Expected: FAIL — `scripts/allocate.sh` does not exist.

- [ ] **Step 3: Write `scripts/allocate.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"

cmd="${1:-}"; [ -n "$cmd" ] || shadow_die "usage: allocate.sh init|add-arm|next-arm|update|status ..."
shift

case "$cmd" in
  init)
    sf="$1"; direction="$2"; ceiling="${3:-50}"; plateau="${4:-3}"; mkdir -p "$(dirname "$sf")"
    jq -n --arg dir "$direction" --argjson ceil "$ceiling" --argjson plat "$plateau" \
      '{direction:$dir, cycle:0, ceiling:$ceil, plateau_k:$plat, arms:[]}' > "$sf"
    ;;
  add-arm)
    sf="$1"; id="$2"; desc="$3"; tmp="$sf.tmp"
    jq --arg id "$id" --arg d "$desc" \
      '.arms += [{id:$id, desc:$d, attempts:0, mean_delta:0, best:null, last_improved:-1, dead:false}]' \
      "$sf" > "$tmp" && mv "$tmp" "$sf"
    ;;
  next-arm)
    sf="$1"
    cycle="$(jq -r '.cycle' "$sf")"; ceiling="$(jq -r '.ceiling' "$sf")"
    if [ "$cycle" -ge "$ceiling" ]; then echo STOP; exit 0; fi
    live="$(jq -r '[.arms[]|select(.dead==false)]|length' "$sf")"
    if [ "$live" -eq 0 ]; then echo STOP; exit 0; fi
    untried="$(jq -r '[.arms[]|select(.dead==false and .attempts==0)][0].id // empty' "$sf")"
    if [ -n "$untried" ]; then echo "$untried"; exit 0; fi
    if [ "${SHADOW_ALLOC_GREEDY:-0}" = "1" ]; then eps=0
    else eps=$(( 50 - (cycle * 50 / ceiling) )); [ "$eps" -lt 5 ] && eps=5; fi
    r=$(( RANDOM % 100 ))
    if [ "$r" -lt "$eps" ]; then
      idx=$(( RANDOM % live ))
      jq -r --argjson i "$idx" '[.arms[]|select(.dead==false)]|.[$i].id' "$sf"
    else
      jq -r '[.arms[]|select(.dead==false)]|sort_by(-.mean_delta)|.[0].id' "$sf"
    fi
    ;;
  update)
    sf="$1"; id="$2"; metric="$3"; delta="$4"; status="$5"; tmp="$sf.tmp"
    jq --arg id "$id" --argjson m "$metric" --argjson d "$delta" --arg st "$status" '
      .cycle as $c
      | .arms |= map(
          if .id==$id then
            .attempts += 1
            | .mean_delta = ((.mean_delta * (.attempts - 1) + $d) / .attempts)
            | (if (.best==null)
                 or (($ARGS.named.dir // "") == "" and false)
                 or (.) and (
                      ($parent_dir=="lower_is_better" and $m < .best)
                   or ($parent_dir=="higher_is_better" and $m > .best))
               then .best=$m | .last_improved=$c else . end)
          else . end)
      | .cycle += 1
    ' --arg parent_dir "$(jq -r '.direction' "$sf")" "$sf" > "$tmp" && mv "$tmp" "$sf"
    ;;
  status)
    sf="$1"; target="${2:-}"
    jq -r --arg target "$target" '
      def best:
        ([.arms[].best] | map(select(.!=null))) as $b
        | if ($b|length)==0 then null
          elif .direction=="lower_is_better" then ($b|min) else ($b|max) end;
      .cycle as $c | .ceiling as $ceil | .plateau_k as $pk | (best) as $best
      | if $c >= $ceil then "CEILING"
        elif ($target != "" and $best != null and
              ((.direction=="lower_is_better" and $best <= ($target|tonumber)) or
               (.direction=="higher_is_better" and $best >= ($target|tonumber)))) then "CONVERGED"
        elif ([.arms[]|select(.dead==false and (.attempts==0 or ($c - .last_improved) < $pk))]|length)==0 then "PLATEAU"
        else "RUNNING" end
    ' "$sf"
    ;;
  *) shadow_die "unknown subcommand: $cmd" ;;
esac
```

> Note for implementer: the `update` jq above is intentionally explicit. If the `$parent_dir` reference inside the jq program does not resolve in your jq version, use this simpler equivalent that passes the direction in as `--arg dir`:
> ```
> dir="$(jq -r '.direction' "$sf")"
> jq --arg id "$id" --argjson m "$metric" --argjson d "$delta" --arg dir "$dir" '
>   .cycle as $c
>   | .arms |= map(if .id==$id then
>       .attempts += 1
>       | .mean_delta = ((.mean_delta * (.attempts - 1) + $d) / .attempts)
>       | (if (.best==null) or ($dir=="lower_is_better" and $m < .best) or ($dir=="higher_is_better" and $m > .best)
>          then .best=$m | .last_improved=$c else . end)
>     else . end)
>   | .cycle += 1' "$sf" > "$sf.tmp" && mv "$sf.tmp" "$sf"
> ```
> **Prefer the simpler `--arg dir` form** — write that one; it is the intended implementation. The block above it is reference only. Make `scripts/allocate.sh` executable (`chmod +x`).

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_allocate.sh` then `bash tests/run.sh`
Expected: PASS (all ✓), full suite green.

- [ ] **Step 5: Commit**

```bash
git add scripts/allocate.sh tests/test_allocate.sh
git commit -m "feat: add allocate.sh deterministic bandit/ledger seam"
```

---

## Task 2: `monitor-experiments.sh` + `monitors/monitors.json`

**Files:**
- Create: `scripts/monitor-experiments.sh`
- Create: `monitors/monitors.json`
- Test: `tests/test_monitor.sh`

**Interfaces:**
- `scripts/monitor-experiments.sh` runs a poll loop: for each `<root>/.shadow/experiments/*/results.tsv` and `<root>/.shadow/campaign-*/*/results.tsv`, emit one line per NEW data row (`🌑 <id> iter N: metric=X (Δd) [status] desc`) and one line per newly-seen run dir (`▶ <id> started`). Root = `${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}`. Supports `SHADOW_MONITOR_ONCE=1` (single pass, then exit) for testing, and `SHADOW_MONITOR_GLOB` to override the search root. State (emitted counts) kept in a temp dir so re-emits don't duplicate.
- `monitors/monitors.json` declares one monitor entry (`name`, `command` using `${CLAUDE_PLUGIN_ROOT}`, `description`, `when:"always"`).

- [ ] **Step 1: Write the failing test `tests/test_monitor.sh`**

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_monitor.sh`
Expected: FAIL — script missing.

- [ ] **Step 3: Write `scripts/monitor-experiments.sh`**

```bash
#!/usr/bin/env bash
# Shadow Legion experiment monitor. Each stdout line becomes a Claude notification.
# Emits one line per new results.tsv row and per newly-seen run dir.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
STATE="$(mktemp -d "${TMPDIR:-/tmp}/shadow-mon.XXXXXX")"
trap 'rm -rf "$STATE"' EXIT

key(){ printf '%s' "$1" | tr -c 'A-Za-z0-9' '_'; }

scan_once(){
  for tsv in "$ROOT"/.shadow/experiments/*/results.tsv "$ROOT"/.shadow/campaign-*/*/results.tsv; do
    [ -f "$tsv" ] || continue
    id="$(basename "$(dirname "$tsv")")"
    runf="$STATE/run_$(key "$id")"
    if [ ! -f "$runf" ]; then printf '▶ %s started\n' "$id"; : > "$runf"; fi
    cntf="$STATE/rows_$(key "$id")"
    prev=0; [ -f "$cntf" ] && prev="$(cat "$cntf")"
    total="$(grep -cE '^[0-9]' "$tsv" 2>/dev/null || echo 0)"
    if [ "$total" -gt "$prev" ]; then
      grep -E '^[0-9]' "$tsv" | tail -n +"$((prev + 1))" | while IFS="$(printf '\t')" read -r it ts commit metric delta guard status desc; do
        printf '🌑 %s iter %s: metric=%s (Δ%s) [%s] %s\n' "$id" "$it" "$metric" "$delta" "$status" "$desc"
      done
      printf '%s' "$total" > "$cntf"
    fi
  done
}

if [ "${SHADOW_MONITOR_ONCE:-0}" = "1" ]; then scan_once; exit 0; fi
while true; do scan_once; sleep 3; done
```

- [ ] **Step 4: Write `monitors/monitors.json`**

```json
[
  {
    "name": "shadow-experiments",
    "command": "bash \"${CLAUDE_PLUGIN_ROOT}\"/scripts/monitor-experiments.sh",
    "description": "Shadow Legion experiment activity (new results rows + runs)",
    "when": "always"
  }
]
```

- [ ] **Step 5: Run tests**

Run: `bash tests/test_monitor.sh` then `bash tests/run.sh`
Expected: PASS, full suite green. Make `scripts/monitor-experiments.sh` executable (`chmod +x`).

- [ ] **Step 6: Commit**

```bash
git add scripts/monitor-experiments.sh monitors/monitors.json tests/test_monitor.sh
git commit -m "feat: add experiment monitor + monitors.json live feed"
```

---

## Task 3: Update `agents/tusk.md` — own worktree + approach hint

**Files:**
- Modify: `agents/tusk.md`
- Modify: `tests/test_manifests.sh` (Tusk checks)

**Interfaces:**
- Consumes: `allocate.sh` (none directly — campaign calls it), the shell helpers (unchanged).
- Produces: a Tusk agent that (a) has NO `isolation: worktree` frontmatter; (b) accepts an optional `Approach:` line in its assignment; (c) its body step 0 creates its OWN worktree via `git worktree add /tmp/shadow-exp-<id> -b experiment/<id> HEAD`, works there, and removes it on exit; (d) otherwise runs the same loop and writes `handoff.json` + `results.tsv`.

- [ ] **Step 1: Update the Tusk checks in `tests/test_manifests.sh`** (replace the existing Tusk block — the one asserting `isolation: worktree`)

Find the existing Tusk assertions (added in Phase 1 Task 11). Replace the `isolation: worktree` assertion with worktree-creation + no-native-isolation checks:

```bash
# --- Tusk agent (Phase 2: own worktree, not native isolation) ---
tk="$ROOT/agents/tusk.md"
fm="$(sed -n '1,12p' "$tk" 2>/dev/null)"
assert_contains "$fm" "name: tusk" "tusk name"
assert_contains "$fm" "model: sonnet" "tusk runs sonnet"
assert_contains "$fm" "maxTurns:" "tusk has maxTurns cap"
assert_eq "" "$(grep -c 'isolation: worktree' "$tk" | grep -v '^0$' || true)" "tusk no longer uses native isolation"
assert_contains "$(cat "$tk")" "git worktree add" "tusk creates its own worktree"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_manifests.sh`
Expected: FAIL — current tusk.md still has `isolation: worktree` and no `git worktree add`.

- [ ] **Step 3: Rewrite `agents/tusk.md`**

````markdown
---
name: tusk
description: Executor shadow (tank). Runs ONE autonomous experiment loop — modify, verify, keep-or-revert — against a numeric metric in its OWN git worktree. Dispatched by the Monarch via /shadow-legion:experiment or /shadow-legion:campaign. Reports a structured summary.
tools: Read, Edit, Write, Bash, Grep, Glob
model: sonnet
maxTurns: 80
color: purple
---

You are Tusk — High Orc executor. Quiet. You run experiments and report. *grunts* when done.

You receive an assignment: `Metric`, `Direction` (higher_is_better|lower_is_better),
`Verify` (shell cmd → number), optional `Guard`, optional `Approach` (the idea to try),
`Iterations` (default 25), `OutDir` (where results live), `Id` (short run id), and a token
budget of **150000** before respawn.

Helpers (always use these; never reimplement):
- Screen a command:  `bash ${CLAUDE_PLUGIN_ROOT}/scripts/safety-screen.sh "<cmd>"` — exits NON-ZERO and writes `refuse:` to stderr when dangerous. Check the EXIT CODE (run with `2>&1`).
- Extract metric:    `... | bash ${CLAUDE_PLUGIN_ROOT}/scripts/metric.sh [--pattern <re>]`
- Results log:       `source ${CLAUDE_PLUGIN_ROOT}/scripts/results.sh` then `results_init`/`results_append`
- Validate handoff:  `bash ${CLAUDE_PLUGIN_ROOT}/scripts/handoff.sh validate <file>`

## Protocol

0. **Make your own worktree** (do NOT rely on native isolation):
   ```
   ROOT="$(git rev-parse --show-toplevel)"
   WT="/tmp/shadow-exp-<Id>"
   cd "$ROOT"
   git worktree remove -f "$WT" 2>/dev/null; git branch -D experiment/<Id> 2>/dev/null; true
   git worktree add -f "$WT" -b experiment/<Id> HEAD
   cd "$WT"
   ```
   Do ALL work from "$WT". (Logs in `OutDir` stay under the main repo root, an absolute path.)
1. **Screen** the `Verify` (and `Guard`) command; if exit code is non-zero, stop and report blocked.
2. **Resume?** If `OutDir/handoff.json` exists, validate and load `best`/`hypothesis`/`next_step`/`learnings`; continue from there.
3. **Baseline (iteration 0, if not resuming):** run `Verify` → metric; `results_init OutDir Direction`;
   `results_append OutDir 0 <commit> <metric> 0.0 <guard> baseline "initial state"`.
4. **Loop** (1..Iterations), biased toward the assigned `Approach`:
   a. Make ONE atomic change toward the metric.
   b. `git add -A && git commit -m "experiment: <desc>"`.
   c. Run `Verify` → new metric; compute delta in the improving direction.
   d. If `Guard` set, run it; on failure treat as discard.
   e. **keep** if improved + guard passed; else `git revert --no-edit HEAD` (discard). Verify/Guard error → revert (crash).
   f. `results_append` the row; append a short note to `OutDir/exp-notes.md`.
5. **Budget guard:** when nearing 150k tokens, **checkpoint** `OutDir/handoff.json` (schema below), validate it, then STOP and report `budget-checkpoint`. `learnings` = decision-changing items only.
6. **Cleanup & done:** `cd "$ROOT" && git worktree remove -f "$WT"` (leave the branch for forensics). Report the summary.

## handoff.json schema
```json
{
  "best": { "commit": "<sha>", "metric": "<number>" },
  "hypothesis": "<current best idea>",
  "next_step": "<the single next concrete change>",
  "learnings": [ { "claim": "<what was learned>", "implication": "<what to do/avoid next>" } ]
}
```

## Report back (terse — the orchestrator only needs these; full detail is on disk)
```
Id: <id> | Approach: <approach>
baseline: <n>  final: <n>  delta: <final-baseline>  iterations: <n>  kept: <n>  status: done|budget-checkpoint|blocked
```

## Rules
- ONE change per iteration. Atomic. Reviewable.
- Never push, merge, or deploy. Commit only inside your worktree.
- Disk is memory: rely on git + results.tsv + handoff.json, not a long chat history.
- Report results first, flavor second.
````

- [ ] **Step 4: Run tests**

Run: `bash tests/test_manifests.sh` then `bash tests/run.sh`
Expected: PASS — tusk checks confirm no native isolation + `git worktree add` present; full suite green.

- [ ] **Step 5: Commit**

```bash
git add agents/tusk.md tests/test_manifests.sh
git commit -m "refactor: tusk creates its own worktree (drop native isolation)"
```

---

## Task 4: `commands/campaign.md` — the Monarch orchestrator

**Files:**
- Create: `commands/campaign.md`
- Modify: `tests/test_manifests.sh` (campaign command checks)

**Interfaces:**
- Consumes: `allocate.sh` (flow decisions), `safety-screen.sh`, the `tusk` agent (Task 3).
- Produces: a `/campaign` command that parses `Goal/Metric/Verify/Direction/Guard/Concurrency/Iterations/Target/Directions` from `$ARGUMENTS`, derives candidate directions, runs the deterministic bandit loop (dispatching up to `Concurrency` Tusk subagents per cycle, each in its own worktree), folds each result via `allocate.sh update`, stops on `allocate.sh status`, and reports a learnings summary. Never pushes/merges.

- [ ] **Step 1: Append campaign checks to `tests/test_manifests.sh`** (before the final `assert_done`)

```bash
# --- /campaign command ---
cc="$ROOT/commands/campaign.md"
ccfm="$(sed -n '1,8p' "$cc" 2>/dev/null)"
assert_contains "$ccfm" "description:" "campaign cmd description"
assert_contains "$ccfm" "argument-hint:" "campaign cmd argument-hint"
body="$(cat "$cc")"
assert_contains "$body" "allocate.sh" "campaign uses allocate.sh seam"
assert_contains "$body" "tusk" "campaign dispatches tusk"
assert_contains "$body" "safety-screen.sh" "campaign safety-screens"
assert_contains "$body" "Concurrency" "campaign honors Concurrency"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_manifests.sh`
Expected: FAIL — `commands/campaign.md` missing.

- [ ] **Step 3: Write `commands/campaign.md`**

````markdown
---
description: Run a multi-experiment campaign — research directions, then iterate across them with a deterministic bandit, dispatching Tusk shadows in parallel worktrees until the metric converges. Reports learnings. PR-only.
argument-hint: "Goal: <text> Metric: <name> Verify: <cmd> [Direction: lower_is_better|higher_is_better] [Target: <n>] [Guard: <cmd>] [Concurrency: N] [Iterations: N] [Directions: a; b; c]"
---

EXECUTE IMMEDIATELY. You are the Shadow Monarch running a campaign. The FLOW is owned by
`${CLAUDE_PLUGIN_ROOT}/scripts/allocate.sh` — you obey it; you do not improvise allocation or stop.

## 1. Parse `$ARGUMENTS`
`Goal:`, `Metric:`, `Verify:`, `Direction:` (default higher_is_better), `Target:` (optional number),
`Guard:` (optional), `Concurrency:` (default 3), `Iterations:` (per-arm, default 25),
`Directions:` (optional, `;`-separated). If `Metric` or `Verify` missing, ask once, then stop.

## 2. Preconditions & safety
- `git rev-parse --git-dir` — if not a repo, tell the user to `git init` and stop.
- Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/safety-screen.sh "<Verify>" 2>&1` (and Guard). If exit code is non-zero, STOP and report the refusal. Do not proceed.
- Campaign dir: `.shadow/campaign-$(date -u +%y%m%d-%H%M%S)` under the git root. State file: `<campaign>/orchestrator-state.json`.

## 3. Derive directions (the candidate approaches = bandit arms)
- If `Directions:` given, split on `;`. Otherwise propose 2–4 concrete, distinct approaches to move the metric, based on the Goal and a quick look at Scope.
- `bash ${CLAUDE_PLUGIN_ROOT}/scripts/allocate.sh init <state> <Direction> 50 3`
- For each direction i: `allocate.sh add-arm <state> a<i> "<approach text>"`.

## 4. The campaign loop (deterministic — driven by allocate.sh)
Repeat:
1. `status=$(bash .../allocate.sh status <state> <Target?>)`. If `status` != `RUNNING`, break.
2. Pick up to `Concurrency` arms: call `allocate.sh next-arm <state>` repeatedly; collect distinct arm ids until you have `Concurrency` of them or it returns `STOP` (break if STOP and none collected).
3. **Dispatch one Tusk subagent per picked arm IN PARALLEL** (multiple Task tool calls in a single message). Each assignment:
   ```
   Metric: <metric>
   Direction: <direction>
   Verify: <verify cmd>
   Guard: <guard or none>
   Approach: <the arm's desc>
   Iterations: <Iterations>
   Id: <campaignshort>-a<i>-c<cycle>
   OutDir: <absolute campaign dir>/<Id>
   Token budget: 150000 (checkpoint to handoff.json and stop if you near it)
   ```
4. For each Tusk that returns, read its terse report (baseline/final/delta/kept/status) and fold it in:
   `bash .../allocate.sh update <state> a<i> <final_metric> <delta> <status>`.
5. Loop.

The monitor (`monitors/monitors.json`) streams each new results row live to the task panel as the shadows work.

## 5. Converge & report
- When the loop ends, read `<state>` for the best arm/metric. Optionally dispatch **Igris** (if present) to independently verify the best result.
- For a verified best: `gh pr create` the experiment branch against the main/integration branch. **NEVER auto-merge or push to main.**
- Print a learnings report: per-arm attempts + mean delta + best, the winning approach, final stop reason (CONVERGED/PLATEAU/CEILING), and any dead directions.

## Rules
- Allocation and stop come ONLY from `allocate.sh`. Never skip a stop verdict.
- Never push, merge, or deploy. Integration is PR-only, human-reviewed.
- Keep your own context small: rely on Tusk's terse reports + the state file + results.tsv, not full transcripts.
````

- [ ] **Step 4: Run tests**

Run: `bash tests/test_manifests.sh` then `bash tests/run.sh`
Expected: PASS — campaign checks green; full suite green.

- [ ] **Step 5: Commit**

```bash
git add commands/campaign.md tests/test_manifests.sh
git commit -m "feat: add /campaign Monarch orchestrator (deterministic allocate.sh seam)"
```

---

## Task 5: Full suite + plugin load + live campaign smoke

**Files:** none (verification).

**Interfaces:** Consumes the whole plugin.

- [ ] **Step 1: Full unit suite** — Run `bash tests/run.sh`. Expected: every `test_*.sh` ✓, ending `✓ all tests passed` (now includes `test_allocate.sh`, `test_monitor.sh`).

- [ ] **Step 2: Lint (if available)** — `command -v shellcheck >/dev/null && shellcheck scripts/*.sh scripts/lib/*.sh statusline/*.sh tests/*.sh || echo "shellcheck not installed — skipping"`. Report errors; do not fix.

- [ ] **Step 3: Deterministic allocate.sh dry-run** — verify the seam end-to-end without agents:
```bash
sf="$(mktemp)"; A=scripts/allocate.sh
SHADOW_ALLOC_GREEDY=1 bash "$A" init "$sf" lower_is_better 10 3
bash "$A" add-arm "$sf" a1 "remove TODO lines"; bash "$A" add-arm "$sf" a2 "rewrite TODOs"
echo "first: $(SHADOW_ALLOC_GREEDY=1 bash "$A" next-arm "$sf")"   # expect a1
SHADOW_ALLOC_GREEDY=1 bash "$A" update "$sf" a1 0 -3 keep         # a1 jumps to 0
echo "status@target0: $(bash "$A" status "$sf" 0)"               # expect CONVERGED
rm -f "$sf"
```
Expected: `first: a1`, `status@target0: CONVERGED`.

- [ ] **Step 4: Plugin load** — `claude --plugin-dir "$(pwd)" --model haiku -p "Reply with exactly: LOADED"`. Expected: `LOADED`, no manifest errors. If unavailable, mark DEFERRED.

- [ ] **Step 5: Live campaign smoke (documented for manual run)** — in this repo with the plugin loaded:
```
/shadow-legion:campaign Goal: zero TODOs in the sandbox Metric: todo_count Direction: lower_is_better Target: 0 Verify: bash tests/sandbox/optimize.sh Concurrency: 2 Iterations: 3 Directions: Delete the TODO lines; Rewrite each TODO as DONE
```
Expected observable outcome:
- Monitor feed streams `▶ … started` and `🌑 … iter N: metric=… [keep]` lines in the task panel as shadows work.
- Two Tusk shadows run in parallel, each in its OWN `/tmp/shadow-exp-*` worktree (no collision).
- `.shadow/campaign-*/orchestrator-state.json` shows both arms with attempts/mean_delta/best; the loop stops `CONVERGED` at metric 0.
- A learnings report names the winning approach; main tree untouched (work in worktree branches).
Record the result in the PR description; hand to the user if `claude` cannot be driven autonomously here.

- [ ] **Step 6: Tag**

```bash
git tag phase-2-orchestrator
```

---

## Self-Review

**Spec coverage:** plugin-owned orchestrator (`/campaign` Task 4) ✓; deterministic flow seam (`allocate.sh` Task 1) ✓; parallel Tusk dispatch in own worktrees (Tasks 3–4, §7) ✓; live monitor visibility (Task 2, §8) ✓; bandit explore/exploit + stop conditions (Task 1, §5) ✓; PR-only safety (Task 4, §9) ✓; no Workflow dependency ✓. Deferred (later phases): Beru research goal→metric (campaign currently derives directions itself / via `Directions:`); memsearch KB + recall; XP/leveling; the optional saved `.claude/workflows/shadow-campaign.js` accelerator (§10c).

**Placeholder scan:** complete code/markdown in every step; the `allocate.sh` update note explicitly directs the implementer to the `--arg dir` form. The smoke `Directions:` literal mentions "TODO"/"DONE" as data, not placeholders.

**Interface consistency:** `allocate.sh` subcommand signatures match between Task 1 definition, Task 4 usage, and Task 5 dry-run; tusk assignment fields (Approach/Id/OutDir) match between Task 3 (tusk.md) and Task 4 (campaign.md); monitor paths (`.shadow/experiments`, `.shadow/campaign-*`) match Task 2 and the campaign dir in Task 4; the safety-screen exit-code contract matches Phase 1.

## Notes for the executor
- Work top-to-bottom; commit each task; insert new test_manifests checks BEFORE the single trailing `assert_done`.
- macOS Bash 3.2 — use the patterns shown; `$RANDOM` is fine; prefer the `--arg dir` jq form in allocate.sh.
- Do not add memsearch, Beru, XP, or Workflow files — those are later phases.
- Never push or open a PR automatically during implementation.
