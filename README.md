# Shadow Legion 🌑

> **An autonomous research & experimentation army for Claude Code.**
> A Shadow-Monarch orchestrator commands specialist agents that research a problem, run
> experiments in isolated git worktrees, allocate effort with a deterministic bandit, prune
> dead ends *with recorded reasons*, remember past campaigns, and hand you a reviewable proposal.
>
> *The weak have their ways. I have my army.*

Inspired by [Karpathy's autoresearch](https://github.com/karpathy/autoresearch) (constraint +
mechanical metric + autonomous iteration) and the Solo-Leveling "Shadow Monarch" motif.

---

## Install

In Claude Code, register this repo as a plugin marketplace and install:

```text
/plugin marketplace add ankush-003/shadow-agents
/plugin install shadow-legion@shadow-legion
```

Then restart Claude Code. Verify it loaded:

```text
/help        # you should see /shadow-legion:experiment and /shadow-legion:campaign
```

### Requirements

The plugin checks these at startup (`scripts/preflight.sh`):

| Tool | Required? | Why |
|------|-----------|-----|
| `git` | ✅ | experiments run in isolated worktrees |
| `jq` | ✅ | JSON state (bandit ledger, handoff, proposal) |
| `claude` | ✅ | the harness itself |
| `memsearch` *(or `uvx`)* | ✅ | semantic memory of past experiments (local ONNX + Milvus Lite — **no server, no API key**). Install: `uv tool install 'memsearch[onnx]'` |
| `gh` | ⬜ optional | not needed — integration is **proposal-only** (a `PROPOSAL.md`, never an auto-PR) |

> **No `gh`, no remote, and no auto-merge required.** The army never pushes or merges; it writes a
> `PROPOSAL.md` with the winning branch and the exact `git merge` command for you to run.

---

## Quickstart

Give the Monarch a goal with a **mechanical metric** and a **verify command** that prints a number:

```text
/shadow-legion:campaign
Goal: reduce p95 latency of the API
Metric: p95_ms
Direction: lower_is_better
Target: 120
Verify: bash scripts/bench.sh | grep p95 | awk '{print $2}'
Concurrency: 3
Iterations: 25
```

The Monarch then:

1. **Researches** the problem (Beru) → proposes concrete experiment *directions*, informed by recall of past campaigns.
2. **Allocates** effort across directions with a deterministic ε-greedy **bandit** (`allocate.sh`).
3. **Experiments** — dispatches **Tusk** shadows in parallel, each in its **own git worktree**, running `modify → verify → keep / revert`.
4. **Prunes** dead directions — *only with a recorded reason* — into a `graveyard.md` so they're never retried.
5. **Verifies** the best result independently (Igris re-runs your Verify on the winning branch).
6. **Proposes** — writes `PROPOSAL.md` (winner, metric delta, branch, manual merge command). You review and merge.

Watch it live: the plugin ships a **monitor** that streams each new result row to the task panel.

For a single experiment without the orchestrator:

```text
/shadow-legion:experiment Metric: todo_count Direction: lower_is_better Verify: bash tests/sandbox/optimize.sh Iterations: 3
```

---

## The Army

| Shadow | Role | Job |
|--------|------|-----|
| **Monarch** | orchestrator (general) | decompose the goal, allocate effort, decide when to stop — drives the deterministic loop |
| **Beru** | researcher (ant king) | turns goal + metric into concrete, distinct directions; recalls prior campaigns |
| **Tusk** | executor (tank) | runs one bounded experiment loop in an isolated worktree |
| **Igris** | verifier (knight) | independently re-verifies the winning result before it's proposed |

*Soldiers (parallel recon swarm) and a leveling system are on the roadmap.*

---

## How it works

```
GOAL ─▶ Monarch ─▶ Beru (research → directions)
                     │
                     ├─ allocate.sh (ε-greedy bandit over directions)
                     ▼
            ┌──── parallel Tusk shadows, each in its own git worktree ────┐
            │  modify → commit → verify → keep / revert  →  results.tsv   │
            └──────────────────────────┬──────────────────────────────────┘
                                        ▼
            fold results into orchestrator-state.json  ·  prune dead dirs → graveyard.md
                                        ▼
                          Igris (independent re-verify of best)
                                        ▼
                            PROPOSAL.md  (you review + merge)
```

**Design principles**

- **Deterministic flow, not LLM-improvised.** Allocation and stop conditions live in a shell seam
  (`allocate.sh`) the orchestrator *obeys* — reproducible and inspectable.
- **Disk is memory.** State lives in git branches + `results.tsv` + JSON ledgers, so each agent runs
  in a small, fresh context (cheaper, less drift). Agents respawn from a compact handoff at a token cap.
- **Markdown is the source of truth.** Experiment notes are plain markdown; memory search works with
  semantic recall (memsearch) *or* a plain grep fallback.
- **Safety first.** Every Verify/Guard command is screened; the army never pushes, merges, or deploys.

---

## Project state (`.shadow/`, git-ignored)

```
.shadow/
├── campaign-<ts>/
│   ├── orchestrator-state.json   # bandit ledger: per-direction attempts / mean-delta / best / dead+reason
│   ├── graveyard.md              # pruned directions (with reasons) — never retried
│   ├── PROPOSAL.md               # the reviewable integration proposal
│   └── <exp-id>/results.tsv      # per-experiment iteration log (karpathy format)
```

---

## Commands & components

- `/shadow-legion:campaign` — full research → bandit-allocated experiments → verify → proposal
- `/shadow-legion:experiment` — a single autonomous experiment loop in a worktree
- `/monarch` — the Shadow Monarch orchestration skill
- Skills: `monarch`, `recall` (semantic memory recall, runs in a forked subagent)
- Agents: `beru`, `tusk`, `igris`
- Monitor: live experiment activity feed (`monitors/monitors.json`)

---

## Development

```bash
bash tests/run.sh          # run the full test suite (plain-bash harness, no deps beyond jq)
```

The plugin is built and tested entirely in Bash 3.2 (macOS-compatible) with `jq`. Each capability has
a paired `tests/test_*.sh`. Implementation plans live in `docs/superpowers/plans/`.

## License

MIT
