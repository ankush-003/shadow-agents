---
description: Run one autonomous experiment loop (modify→verify→keep/discard) against a numeric metric in an isolated worktree. Dispatches the Tusk shadow.
argument-hint: "Metric: <name> Verify: <cmd> [Direction: lower_is_better|higher_is_better] [Guard: <cmd>] [Iterations: N]"
---

EXECUTE IMMEDIATELY.

## 1. Parse `$ARGUMENTS`
Extract: `Metric:`, `Verify:`, `Direction:` (default `higher_is_better`), `Guard:` (optional),
`Iterations:` (default 25). If `Metric` or `Verify` is missing, ask once (batched) and stop.

## 2. Preconditions
- Confirm a git repo: `git rev-parse --git-dir` — if not, tell the user to `git init` and stop.
- Pick a run id and OutDir: `.shadow/experiments/exp-$(date -u +%y%m%d-%H%M%S)` under the git root.

## 3. Safety screen
Screen the Verify command (and Guard if set):
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/safety-screen.sh "<Verify>"`
This script EXITS NON-ZERO and writes `refuse: <reason>` to stderr when the command is dangerous; it prints `ok` and exits 0 when safe. Check the EXIT CODE — if it is non-zero, STOP and report the refusal reason to the user. Do not dispatch. (Capture stderr too, e.g. run with `2>&1`, so you can show the reason.)

## 4. Dispatch Tusk
Spawn the `tusk` subagent (it runs in its own worktree via its `isolation: worktree` setting).
Pass the assignment verbatim:

```
Metric: <metric>
Direction: <direction>
Verify: <verify cmd>
Guard: <guard cmd or none>
Iterations: <N>
OutDir: <absolute path to the run dir>
Token budget: 150000 (checkpoint to handoff.json and stop if you near it)
```

## 5. Report
Relay Tusk's summary: baseline→final metric, kept/discarded counts, and whether it
finished or hit `budget-checkpoint` (in which case tell the user re-running `/experiment`
will resume from `handoff.json`).
