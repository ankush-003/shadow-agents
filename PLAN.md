# Shadow Legion — Autonomous Research & Experimentation Army

> A Claude Code plugin: a Shadow-Monarch orchestrator commands ranked specialist
> agents that research problems, define metrics, and run autonomous experiments
> in isolated git worktrees — learning collectively, and leveling up their craft.

Working name: **shadow-legion** (matches the `shadow-agents` workspace; rename freely).

---

## 1. Vision

You give the Monarch a **goal**. The Monarch (orchestrator) does not solve it directly.
It:

1. **Spawns researchers** to understand the problem and define the *ideal, mechanical metric* + a `Verify` command.
2. **Dispatches experiment soldiers**, each in its **own git worktree**, to run the
   Karpathy loop: `modify → commit → verify → keep / revert`.
3. **Collects every result** into a shared, observable state DB (memsearch-backed).
4. **Learns** across all experiments — which directions pay off, which are dead — and
   reallocates effort (invest in winners, prune losers).
5. The army **levels up**: agents accumulate *role craft* (transferable skill), earn
   XP/rank, and ascend to stronger models as they prove themselves.

The human can watch the whole campaign live: what's running, what's working, what's been learned.

---

## 2. The two memories (critical design split)

Keep these **physically separate**. Mixing them is the main failure mode.

| | **Project Knowledge Base** | **Role Skill Library** |
|---|---|---|
| Holds | Experiment-specific *facts* | Transferable *craft / methodology* |
| Example | "LR=0.04 → val_bpb 0.993; GeLU worse" | "As a researcher: pin the metric before exploring" |
| Scope | Per **project** (disposable) | Per **role**, **cross-project** (durable) |
| Owner | Orchestrator | The agent role itself |
| Backing | memsearch project collection (`.shadow/experiments/*.md`) | role `SKILL.md` files + memsearch global collection |
| Grows via | Every experiment result | Distillation of proven techniques (leveling) |
| Used for | "Have we tried this? What worked?" | "How do I do my job better?" |

**Soldiers are generic.** A Soldier is infantry. Leveling a Soldier makes it better at
*being infantry* (recon/parallel craft), **not** an expert on one experiment. Experiment
knowledge lives in the project KB and is read by *whoever* works that project next.

This mirrors memsearch's `memory-to-skill`: a recurring *technique* gets promoted into a
reusable role skill; a one-off *fact* just gets logged to the KB.

---

## 3. The army (roster → role → maps to)

| Shadow | Rank/Role | Job in the campaign | Lineage |
|---|---|---|---|
| **Monarch** | Orchestrator (General) | Decompose goal, allocate, learn, decide stop | arise `monarch` skill + autoresearch orchestrator |
| **Beru** | Researcher | Understand problem, find SOTA, **define ideal metric + Verify cmd** | autoresearch `plan`/`improve`/`learn` + `deep-research` skill |
| **Igris** | Knight (verifier) | **Independent** verify of experiment claims, regression/quality gate | autoresearch `regression`/`security` + `code-review` |
| **Tusk** | Tank (executor) | Run the heavy modify→verify→keep loop in a worktree | karpathy `program.md` loop / autoresearch core |
| **Soldiers** | Infantry (swarm) | Parallel recon + cheap parallel experiment sweeps | arise `soldier` + autoresearch `scenario` |

Each role has **ranks** (E→D→C→B→A→S→SS→SSS, reuse arise thresholds). Rank gates capability (§6).

---

## 4. Architecture

```
                          ┌──────────────────────────────┐
            GOAL  ───────▶│        MONARCH (skill)        │
                          │  decompose · allocate · learn │
                          └───────────────┬───────────────┘
                  ┌───────────────────────┼───────────────────────┐
                  ▼                        ▼                        ▼
            ┌──────────┐            ┌──────────┐             ┌──────────┐
            │   BERU   │            │   TUSK   │  …N worktrees│ SOLDIERS │
            │researcher│            │ executor │             │  swarm   │
            └────┬─────┘            └────┬─────┘             └────┬─────┘
   defines metric│        experiment loop│ in git worktree        │ recon/sweep
        + Verify │   modify→commit→verify│ keep/revert→results.tsv│
                  ▼                        ▼                        ▼
            ┌──────────────────────────────────────────────────────────┐
            │   SHARED BRAIN (memsearch)  ·  .shadow/                     │
            │   experiments/*.md  ·  STATE.md  ·  knowledge-base index    │
            └───────────────────────┬──────────────────────────────────┘
                                     ▼
                         ┌────────────────────┐
                         │  IGRIS (verifier)  │  independent check before "keep" is trusted
                         └────────────────────┘
            human watches ▶ STATE.md / statusline / /status
```

### Component layout (single installable plugin)

```
shadow-legion/
├── .claude-plugin/
│   ├── plugin.json              # name, version, commands, agents, skills, hooks
│   └── marketplace.json         # so `/plugin install shadow-legion@...` works
├── skills/
│   ├── monarch/SKILL.md         # orchestrator persona + dispatch (thin routing)
│   ├── campaign/SKILL.md        # the orchestrator LEARNING LOOP (§5)
│   └── recall/SKILL.md          # context:fork memsearch recall of project KB
├── commands/
│   ├── campaign.md              # /campaign  <goal>  → full research→iterate run
│   ├── research.md              # /research  → define metric+Verify (Beru)
│   ├── experiment.md            # /experiment → one worktree loop (Tusk)
│   ├── status.md                # /status    → live campaign dashboard
│   ├── learnings.md             # /learnings → what worked / what didn't
│   ├── promote.md               # /promote   → distill role craft into a skill (level up)
│   └── extract.md               # /extract   → mint a new specialist (arise ritual)
├── agents/
│   ├── beru.md / beru.ascended.md
│   ├── igris.md / igris.ascended.md
│   ├── tusk.md  / tusk.ascended.md
│   └── soldier.md / soldier.ascended.md
├── roles/                       # ROLE SKILL LIBRARY (the durable craft, §2/§6)
│   ├── researcher/playbook.md   # grows as Beru levels
│   ├── knight/playbook.md
│   ├── tank/playbook.md
│   └── infantry/playbook.md
├── scripts/
│   ├── worktree.sh              # add/list/merge/cleanup experiment worktrees
│   ├── xp-tracker.sh            # rank/level state (from arise) + outcome-based XP
│   ├── xp-hook.sh               # PostToolUse → award/penalize on verify outcome
│   ├── state-render.sh          # rebuild STATE.md from .shadow/experiments/*.md
│   └── kb-index.sh              # memsearch index of the project KB
├── hooks/hooks.json             # safety (uditgoenka set) + XP + state-render
├── output-styles/monarch.md     # themed notifications
└── statusline/legion.sh         # 「Lv.x」rank · running N · best metric
```

### Plugin spec notes (validated against official docs)

Confirmed via `code.claude.com/docs` (plugins-reference, sub-agents, hooks, skills, statusline):
- **Only `plugin.json` goes in `.claude-plugin/`.** Everything else auto-discovers from root dirs
  (`skills/`, `commands/`, `agents/`, `hooks/hooks.json`, `output-styles/`) — no inline arrays needed.
- **Worktree isolation is native:** `agents/*.md` supports `isolation: worktree` (and the Workflow
  tool exposes the same). So experiment agents isolate declaratively — we don't shell out
  `git worktree add` ourselves. Lifecycle hooks `WorktreeCreate`/`WorktreeRemove` exist for setup/teardown.
- **Native memory + skill preload on agents:** `memory: user|project|local` and `skills: [..]`.
  → role craft can ride `memory: user` (cross-project) and preload its role skill on spawn; the
  project KB stays in memsearch. (We still use memsearch for *semantic recall*; native memory is the
  cheap always-loaded layer.)
- **Per-agent budget levers:** `maxTurns` (+ `effort`, `model`) on agents — combine with the token
  cap for the respawn guard (§6c).
- **Result collection hooks:** `SubagentStop` / `TaskCompleted` fire when an agent finishes → drive
  XP + ledger folding without polling.
- **Statusline** declared as `"statusline": "./statusline/legion.sh"` in plugin.json; its stdin JSON
  includes `context.total_tokens / max_tokens / percent_used` — handy for the live budget gauge.
- `context: fork` + `agent:` on skills is documented → the `recall` skill design is valid.

### Storage map — two scopes (answers "where do we store what")

The persistent unit is the **role**, not an individual soldier (soldiers are ephemeral,
spawned per task). So **role state is global & cross-project**; **experiment state is
project-local & disposable.**

```
~/.shadow/                         # GLOBAL — the army's permanent record (survives projects)
├── hunter.json                    # overall account XP/rank (statusline gamification)
├── roles/
│   ├── researcher/
│   │   ├── playbook.md            # positive craft — what leveling GROWS (§6)
│   │   ├── antipatterns.md        # negative craft — learnings from FAILURES (§6b)
│   │   └── rank.json              # {xp, level, rank, missions, wins, losses, model_tier}
│   ├── knight/  · tank/ · infantry/   (same shape)
└── roster.json                    # registry of /extract-ed specialists

<repo>/.shadow/                    # PROJECT — disposable, gitignored
├── STATE.md                       # human-readable live dashboard (auto-rendered)
├── campaign.json                  # goal, metric, Verify, token+iter budgets, stop-conditions
├── orchestrator-state.json        # bandit ledger: per-direction attempts/mean-delta/best (§5)
├── graveyard.md                   # dead directions — never retry (failure KB, §6b)
├── experiments/exp-<id>.md        # one per experiment: hypothesis/metric/result/learning (wins AND losses)
├── results.tsv                    # roll-up (karpathy format)
└── worktrees/exp-<id>/            # git worktrees + each agent's handoff.md (§6c)
```

Rule of thumb: **transferable craft → global role dir; experiment facts → project dir.**
A leveled researcher carries its `playbook.md` everywhere; it does *not* carry project A's
metric numbers into project B.

---

## 5. The two core loops

### A. Orchestrator (Monarch) learning loop — `skills/campaign`

```
1. INTAKE   goal → (Beru) research → ideal metric + Verify cmd + scope  [human confirms once]
2. PLAN     break into experiment "directions" (hypotheses to test)
3. ALLOCATE pick next direction(s) — explore/exploit policy below
4. DISPATCH spawn experiment agents — each gets its OWN worktree + token budget (§6c)
5. COLLECT  fold each agent's handoff.md + exp-<id>.md into orchestrator-state.json
6. VERIFY   high-impact "keep"s go to Igris for independent confirmation
7. LEARN    update KB: promising → reinforce; dead → graveyard.md; failures → role antipatterns (§6b)
8. STOP?    metric target met → CONVERGED · plateau → PLATEAU · token/iter budget → CEILING
            else GOTO 3
```

Key: step 7 is what makes it *learn* — `orchestrator-state.json` tracks per-direction
outcome history so step 3 stops throwing soldiers at dead ends.

#### Explore vs. exploit (step 3, concrete)

Treat each experiment **direction** (a family of hypotheses) as a **bandit arm**. The ledger
tracks per direction: `attempts`, `mean_delta`, `best`, `last_improved_cycle`.

- **ε-greedy, budget-annealed:** with prob ε pick an under-explored/untried direction, else the
  best `mean_delta`. **ε decays as token budget depletes** → explore early, exploit late.
  (e.g. `ε = 0.5 * remaining_budget_fraction`, floor 0.05.)
- **Plateau → forced explore:** if the leading direction hasn't improved in K cycles, drop it to
  the graveyard and force exploration of a new arm. Repeated global plateau → `PLATEAU` stop.
- **Deterministic seam:** the policy lives in `scripts/allocate.sh next-arm orchestrator-state.json`
  (like uditgoenka's `orchestrate.sh`) — the LLM reads the ledger and obeys the script, so routing
  is reproducible and inspectable, not hallucinated.

### B. Experiment loop (Tusk/soldier, inside a worktree) — `commands/experiment`

Straight from karpathy `program.md`, hardened with uditgoenka's safety:

```
0. BASELINE  run Verify → record iteration 0 in results.tsv
LOOP (bounded, default 25; opt-in unlimited):
  1. REVIEW   read recent results.tsv + git log (git = memory)
  2. RECALL   memsearch project KB: "tried this before?"  (avoid repeats)
  3. MODIFY   one atomic change
  4. COMMIT   experiment: <desc>
  5. VERIFY   run Verify → metric; SAFETY-SCREEN the cmd first
  6. GUARD    run Guard (tests/build) → must pass
  7. DECIDE   improved+guard → keep · else git revert HEAD
  8. LOG      append results.tsv + write exp-<id>.md (hypothesis, result, learning)
STOP → write handoff.json, report to Monarch
```

---

## 6. Leveling up (your open question, answered)

Three layers. Only the first is what you were unsure about; it's the important one.

### Layer 1 — Role craft (the real "level up"; transferable, generic)
- Each role has a `roles/<role>/playbook.md` — distilled, **experiment-agnostic** heuristics
  about *doing that role well* (how a researcher picks metrics; how a tank does safe bulk edits).
- On spawn, an agent's system prompt **loads its role playbook** → it starts smarter than last time.
- After a campaign, `/promote` runs a distillation pass (memsearch `memory-to-skill` style):
  scan that role's recent wins → extract any *recurring technique* → append/refine the playbook,
  or graduate a big one into a standalone role `SKILL.md`. **This is leveling.**
- Generic by construction: only patterns that generalize across experiments are kept;
  one-off facts are rejected (they go to the project KB instead).

### Layer 2 — Rank & XP (gamified progress signal, from arise)
- `xp-tracker.sh` already does E→D→…→SSS. Re-point XP from "commits" to **experiment outcomes**:
  confirmed `keep` (+big), verified-by-Igris (+), discard (0), crash (penalty/no-XP).
- Rank gates capability:

  | Rank | Model | Tools | Iter budget | Autonomy |
  |---|---|---|---|---|
  | E–D | sonnet | read-only / Edit | 10 | suggest only |
  | C–B | sonnet | + Bash, worktree | 25 | auto keep/revert in worktree |
  | A–S | **opus** (ascend) | + commit | 50 | self-directed within direction |
  | SS+ | **opus** | + propose PR | unlimited (opt-in) | can recommend ship (never auto) |

  **Model rule: Opus only at rank A and above; everything below A runs on sonnet** (no haiku —
  experiment reasoning needs the floor quality). Opus is the rank-A `.ascended` reward, kept rare.

### Layer 3 — Ascension & speciation (from arise `.ascended` + `/extract`)
- `.ascended.md` = same agent, stronger model — unlocked by rank (the `/domain` toggle).
- `/extract`: when a Soldier repeatedly wins a *kind* of task, the Monarch distills it into a
  **new named specialist** — the army literally grows new ranks over time.

> Net: soldiers stay generic; what compounds is (a) their role playbook, (b) the project KB,
> (c) the roster itself. Experiment facts never pollute a soldier's identity.

---

## 6b. Learning from failures (first-class)

A failed experiment is data, not waste. Distinguish two failure kinds (karpathy):

- **discard** — code ran, idea was *worse than baseline*. A **valid negative result.** Small XP
  (you learned something). Hypothesis-level signal.
- **crash** — code broke (OOM, bug). No metric. Zero/penalty XP. Only signal: "this approach is
  fragile here."

Where failure knowledge flows:

1. **Project KB** — every `exp-<id>.md` records *why* it failed. Dead directions roll up into
   `graveyard.md`; the bandit deprioritizes them and the experiment loop's **RECALL** step reads it
   to avoid re-running known losers.
2. **Role craft (the durable part)** — if a failure reveals a *generalizable* anti-pattern, it goes
   to `~/.shadow/roles/<role>/antipatterns.md` ("as a tank, never bulk-rename before the test
   harness is green"). On spawn, an agent loads `playbook.md` **and** `antipatterns.md` → it stops
   repeating class-level mistakes across projects. **Negative craft levels the role just like
   positive craft.**

XP must reward *valid learning*, not just wins — otherwise agents avoid risky-but-informative
experiments. Confirmed keep ≫ verified-by-Igris > valid discard > 0 (crash).

---

## 6c. Token economics & agent respawn guard

Two cost levers: **who gets the expensive model**, and **how long any agent is allowed to run**.

### Model tiering (cost control)
- **Default = sonnet for the whole army** (E through S below rank A). **Opus only at rank A+**, as the
  `.ascended` reward — kept rare. Even at A+, Opus is reserved for the hardest single steps (Igris
  final verify, Beru deep synthesis); the churny experiment loop stays on sonnet.
- No haiku: experiment reasoning needs a quality floor. Rank — not generosity — gates Opus.

### The respawn guard (your idea — core to keeping cost + hallucination down)
Each spawned agent runs under a **hard token budget** (campaign-configurable, e.g. 80k). State
lives on **disk** (git branch + `results.tsv` + notes), so an agent is near-stateless and cheap to
replace. When an agent approaches its cap mid-experiment:

```
1. CHECKPOINT  write worktrees/exp-<id>/handoff.md — STRICTLY high-signal, not the transcript:
               · best commit + metric so far (the one number that matters)
               · current hypothesis + the single next concrete step
               · significant learnings ONLY — things that change what to try next
                 (a confirmed cause, a dead end, a constraint discovered). NOT a play-by-play.
               · pointers, not prose: reference commits/files/results.tsv rows instead of quoting
2. DIE         agent exits cleanly
3. RESPAWN     Monarch starts a FRESH agent loading ONLY:
               role playbook + antipatterns + handoff.md + KB recall
               → small context, continues from disk state
```

**Handoff quality gate (enforced via schema):** the checkpoint is a structured object
(`{best, hypothesis, next_step, learnings[]}`), and `learnings[]` is validated to be
*decision-changing* items — a respawned agent must be able to act on it without re-reading history.
"Tried X, it was fine" is dropped; "X regresses the metric because Y — stop trying X-family" is kept.
Full detail always lives on disk (git log + `results.tsv` + `exp-<id>.md`); the handoff is the index.

Why: carrying a long transcript raises both **cost** (re-billed every turn) and **hallucination**
(stale context drift). A fresh agent + compact handoff is cheaper and sharper. This is the same
principle as the harness's own context-summarization and Workflow resume.

### How to enforce the budget (native levers, validated)
- **`maxTurns`** on the experiment agent caps agentic turns (hard, native) — first line of defense.
- **Iterations** bound the experiment loop (karpathy already does).
- **Tokens:** Workflow's `budget.spent()/remaining()` gives true per-run accounting; the respawn
  pattern is native (`while budget.remaining() > floor { agent(handoff) }`). For plugin-native runs,
  a `PostToolUse` hook writes a running token estimate to `worktrees/exp-<id>/tokens` and the loop
  checkpoints when over.
- **Collection is event-driven:** `SubagentStop` / `TaskCompleted` hooks fire on agent finish →
  award XP and fold the result into the ledger without polling.

> Net: cost is governed by (1) rank-gated models, (2) per-agent token caps with disk-backed
> respawn, (3) bandit allocation that stops funding dead directions.

---

## 7. Git worktree isolation (native)

- **Declarative, not hand-rolled:** experiment agents set `isolation: worktree` in their
  `agents/*.md` frontmatter (or via the Workflow `agent(..., {isolation:'worktree'})` option). Claude
  Code provisions the worktree; `WorktreeCreate`/`WorktreeRemove` hooks handle any extra setup/cleanup.
- Gives every agent a **private filesystem + branch** → parallel experiments never collide;
  the branch *is* its log (karpathy git-as-memory, per agent).
- `keep` that's Igris-verified → Monarch opens a **PR** (never auto-merge/push — §9).
- `discard`/`crash` → branch retained for forensics; worktree torn down by the framework.
- superpowers' `using-git-worktrees` skill remains a fallback for harnesses lacking native isolation.

---

## 8. Shared brain & observability (memsearch)

- **Source of truth = markdown** under `.shadow/experiments/*.md` (memsearch philosophy).
  memsearch indexes it → semantic recall ("have we tried X?") via the `recall` skill (`context:fork`).
- **One project collection** (don't give each soldier its own Milvus — too heavy). Agents *write*
  notes; the orchestrator and recall skill *read*. Role craft uses a separate **global** collection.
- **Live dashboard**: `state-render.sh` rebuilds `STATE.md` on every experiment write (hook), so the
  human sees running experiments, metrics, and learnings without interrupting agents. `/status`
  prints it; statusline shows campaign rank + running count + best metric.

---

## 9. Safety (non-negotiable, from uditgoenka)

- **Never push/deploy/merge-to-main without explicit human approval.** Worktree commits are fine;
  integration is **PR-only**: verified keeps become `gh pr create` against the project's main/integration
  branch, and a **human reviews & merges**. The army never merges or pushes on its own.
- `screen-cmd` on every `Verify`/`Guard`/derived command before first run (block `rm -rf`, `curl|sh`, creds, outbound writes).
- Bounded by default; `unlimited` is opt-in per campaign.
- DB/data-migration experiments behind a localhost/`_test`-suffix allowlist only.
- Hooks: reuse uditgoenka's `scout-block`, `privacy-block`, `dangerous-cmd-block`, `simplify-gate`.

---

## 10. Phased roadmap

**Phase 0 — Skeleton (installable, no-op)**
- `plugin.json` + `marketplace.json`; verify `/plugin install` works locally; statusline + output-style.

**Phase 1 — Single experiment loop (the heart)**
- `commands/experiment.md` (karpathy loop + safety screen) running in a worktree.
- `worktree.sh`, `results.tsv`, `exp-<id>.md`. Manual metric/Verify. No orchestrator yet.
- *Milestone:* hand it a metric, it autonomously improves it in isolation.

**Phase 2 — Research → metric**
- `agents/beru.md` + `commands/research.md`: turn a goal into metric + Verify (wraps `deep-research`).
- *Milestone:* goal in → runnable experiment config out.

**Phase 3 — Orchestrator + learning**
- `skills/campaign` loop, `orchestrator-state.json` (bandit allocation), `/campaign`, `/learnings`.
- Igris independent verify. Parallel worktrees via soldiers.
- *Milestone:* goal in → army runs many experiments → converges, with a learnings report.

**Phase 4 — Memory & observability**
- memsearch integration (project KB + recall skill), `STATE.md` auto-render, `/status` dashboard.
- *Milestone:* human watches live; agents stop repeating tried experiments.

**Phase 5 — Leveling**
- `xp-tracker` repointed to outcomes; rank-gated capability table; `.ascended` ascension.
- `roles/*/playbook.md` + `/promote` distillation; `/extract` speciation.
- *Milestone:* across campaigns, agents measurably start stronger.

---

## 10b. Execution model — how a campaign actually runs

**Default substrate = the Workflow tool**, because its agents are **visible inside Claude Code**:
they render live in the `/workflows` progress tree (grouped by phase), so you watch the army work.
A headless `claude -p` driver would run as invisible OS processes — rejected as the default for
exactly this reason; kept only as an optional **detached/overnight** mode (§ below).

Workflow also natively provides everything the loop needs:
- **per-agent worktree isolation** — `agent(prompt, {isolation:'worktree'})`
- **fresh context per agent** — every `agent()` call is its own context window → low hallucination/cost
- **real token budget + respawn** — `budget.spent()/remaining()`; respawn = another `agent()` with handoff
- **concurrency cap** — `parallel()` over a slice of size `Concurrency`
- **deterministic control flow** — real JS loop for the bandit allocation

### Entry point
`/campaign "<goal>" Concurrency: 4 Iterations: 25 Tokens: 150000` — the command is the explicit
opt-in (`Tokens:` default **150k** per agent before respawn). The Monarch runs research (Beru) to define the metric, writes `campaign.json`, then
**authors and runs a Workflow script**. You watch agents in `/workflows`.

Args parsed uditgoenka-style from `$ARGUMENTS`: `Goal: Scope: Metric: Verify: Guard:`
`Iterations: N|unlimited`, **`Concurrency: N`** (default 3), `Tokens: N` (per-agent cap), `--dry-run`.

### The orchestrator as a Workflow (sketch)
```js
export const meta = { name: 'shadow-campaign',
  description: 'Research → define metric → run bandit-allocated experiments in worktrees',
  phases: [{title:'Research'},{title:'Experiment'},{title:'Verify'}] }

phase('Research')                                   // Beru defines metric + Verify
const cfg = await agent(researchPrompt, {schema: METRIC_CFG, model:'sonnet', phase:'Research'})

let cycles = 0
while (!converged && !plateau && budget.remaining() > FLOOR && cycles++ < CEILING) {
  phase('Experiment')
  const arms = allocate(ledger, /*explore/exploit, ε annealed to budget*/) .slice(0, CONCURRENCY)
  const results = await parallel(arms.map(arm => async () => {
    // respawn loop: fresh agent each pass, resumes from handoff.md on disk
    let r, done = false
    while (!done && budget.remaining() > FLOOR) {
      r = await agent(experimentPrompt(arm), {            // ← visible in /workflows
            isolation:'worktree', model: rankTier(arm.role),
            label:`exp:${arm.id}`, phase:'Experiment', schema: EXP_RESULT })
      done = r?.status !== 'budget-checkpoint'             // exited on token cap → loop respawns it
    }
    return r
  }))
  phase('Verify')                                          // Igris independently verifies keeps
  for (const keep of results.filter(r => r?.status==='keep'))
    keep.verified = await agent(verifyPrompt(keep), {model:'opus', phase:'Verify', schema: VERDICT})
  foldIntoLedger(ledger, results)        // update bandit arms, graveyard, role antipatterns (§6b)
  renderState(results)                   // rebuild STATE.md for the human
}
// verified keeps → gh pr create (NEVER auto-merge, §9). PRs await human review.
return summary(ledger)
```

### Respawn (your token guard, native)
Each `agent()` runs under the shared `budget`. An experiment agent that hits its per-agent cap
writes `handoff.md` and returns `status:'budget-checkpoint'`; the `while` loop spawns a **fresh**
`agent()` that loads only `handoff.md` + role craft + KB recall → small context, continues from the
git/worktree state. No long transcript is ever re-billed.

### Concurrency
`Concurrency: N` = size of each `parallel()` batch (≤ the engine's own min(16, cores−2) cap). New
arms launch only as the batch drains. Recommend 3–5.

### Optional: detached/overnight mode
For runs that must survive quitting Claude Code, the **same engine** is mirrored by
`scripts/legion.sh` spawning bounded `claude -p` processes per worktree (memsearch's `claude -p`
pattern). Trade-off: true detachment, but **not visible** in the CC UI — use only for unattended
overnight campaigns.

---

## 11. Decisions

**Resolved**
- **Theme:** full Solo-Leveling flavor (arise style). ✅
- **Storage:** role state global (`~/.shadow/roles/`), experiment state project-local (`<repo>/.shadow/`). ✅ (§4)
- **Leveling unit:** the role, not the individual soldier; craft is transferable, facts are not. ✅ (§6)
- **Failures:** first-class — project `graveyard.md` + role `antipatterns.md`. ✅ (§6b)
- **Explore/exploit:** ε-greedy, budget-annealed, plateau-forced, in `allocate.sh`. ✅ (§5)
- **Cost control:** rank-gated models + per-agent token cap with disk-backed respawn. ✅ (§6c)

- **memsearch:** HARD dependency. ✅ Feasible with no server — Milvus Lite (local file) + ONNX
  bge-m3 (local, no API key). Requires `uvx`/`pipx` + one-time ~558MB model download. SessionStart
  **preflight** fails loudly with install instructions if the CLI is absent.
- **Concurrency:** runtime **argument** `Concurrency: N` (default 3), uditgoenka-style parsing. ✅
- **Domain:** generic from the start. ✅
- **Auto-merge:** **PR-only** into the project's main/integration branch; Igris verifies → Monarch
  opens a PR → **human reviews & merges.** Never auto-merge, never auto-push. ✅ (§9, §10b)
- **Execution substrate:** **Workflow tool** as default — agents are **visible in `/workflows`**
  inside Claude Code, with native worktree isolation + token budget + respawn. Headless `claude -p`
  driver kept only as an optional detached/overnight mode (not visible). ✅ (§10b)

**Requirements the user must have installed**
- `git` (worktrees), `gh` (PR creation), `jq`, a Python toolchain with `uvx` or `pipx` (memsearch),
  and `claude` on PATH (headless driver). Preflight checks all of these.

- **Per-agent token cap:** **150k** default (`Tokens:`), then respawn from handoff. ✅
- **Handoff:** strict high-signal only — structured `{best, hypothesis, next_step, learnings[]}`,
  `learnings[]` validated as decision-changing; disk holds full detail. ✅ (§6c)
- **Rank→model:** sonnet for all ranks below A; **Opus only A+** (`.ascended` reward); no haiku. ✅ (§6)

**All major decisions resolved — ready to scaffold Phase 0 + 1.**
```
