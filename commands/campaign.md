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
3. **Dispatch one `tusk` subagent per picked arm IN PARALLEL** (multiple Task tool calls in a single message). Each assignment:
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
