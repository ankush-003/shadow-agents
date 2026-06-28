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
- Index + recall prior knowledge: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/kb.sh index` (keeps the memsearch collection current; no-op without memsearch), then use the `recall` skill (or `kb.sh search "<metric/goal terms>"`) to learn what past campaigns tried for this metric. Bias the derived directions toward untried/promising angles and AWAY from anything already recorded dead in a prior graveyard.
- If `Directions:` given, split on `;`. Otherwise propose 2–4 concrete, distinct approaches to move the metric, based on the Goal and a quick look at Scope.
- `bash ${CLAUDE_PLUGIN_ROOT}/scripts/allocate.sh init <state> <Direction> 50 3`  (defaults: `ceiling=50` max campaign cycles, `plateau_k=3` cycles-without-improvement before PLATEAU — distinct from `Iterations` which is the per-arm loop count passed to each Tusk, and `Concurrency` which is the parallel batch size)
- For each direction i: `allocate.sh add-arm <state> a<i> "<approach text>"`.

## 4. The campaign loop (deterministic — driven by allocate.sh)
Repeat:
1. `status=$(bash .../allocate.sh status <state>)` — pass `<Target>` as a second argument ONLY if the user supplied a Target (i.e., `allocate.sh status <state> <Target>` when Target is set, `allocate.sh status <state>` otherwise). If `status` != `RUNNING`, break — this is the ONLY thing that ends the campaign loop.
2. Collect up to `Concurrency` distinct arm ids by calling `allocate.sh next-arm <state>` repeatedly. If it returns `STOP`, stop collecting for THIS cycle and dispatch whatever you have. If zero arms were collected AND `STOP` was returned, do not spin — re-evaluate at step 1 (the `allocate.sh status` check is the ONLY thing that ends the campaign loop).
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

## 4b. Prune dead directions (reasoned + verified)
After updating arms for this cycle, check for dead candidates:
1. `cands=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/allocate.sh dead-candidates <state> 2)` — arms with ≥2 consecutive non-improving attempts.
2. For EACH candidate arm, derive the REASON it failed from that arm's Tusk reports/handoff learnings this campaign (e.g. "every variant regressed the metric because X"). Do not invent a reason — quote the shadow's own learning. If you cannot find a concrete reason, do NOT kill the arm yet (give it one more cycle).
3. With a concrete reason in hand, prune it:
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/allocate.sh mark-dead <state> <armid> "<reason>"`
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/graveyard.sh append <campaign>/graveyard.md <armid> "<desc>" "<reason>"`
A dead arm is skipped by `next-arm` and `status` automatically. Never kill an arm without a recorded reason.

5. Loop.

The monitor (`monitors/monitors.json`) streams each new results row live to the task panel as the shadows work.

## 5. Converge & report
- When the loop ends, read `<state>` for the best arm/metric. Optionally dispatch **Igris** (if present) to independently verify the best result.
- For a verified best: `gh pr create` the experiment branch against the main/integration branch. **NEVER auto-merge or push to main.**
- Print a learnings report: per-arm attempts + mean delta + best, the winning approach, final stop reason (CONVERGED/PLATEAU/CEILING), and any dead directions.
- Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/allocate.sh dead-report <state>` and include the pruned directions with their recorded reasons in the report.

## Rules
- Allocation and stop come ONLY from `allocate.sh`. Never skip a stop verdict.
- Never push, merge, or deploy. Integration is PR-only, human-reviewed.
- Keep your own context small: rely on Tusk's terse reports + the state file + results.tsv, not full transcripts.
