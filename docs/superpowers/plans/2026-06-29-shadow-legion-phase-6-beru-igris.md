# Shadow Legion — Phase 6: Beru (Researcher) + Igris (Verifier) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the two missing specialist shadows — **Beru** (researcher: turns a goal+metric into concrete, distinct experiment directions, informed by KB recall) and **Igris** (verifier: independently re-runs Verify on the winning branch and judges the result before it's proposed) — and wire them into `/campaign` so the Monarch *dispatches specialists* instead of improvising research inline and skipping verification.

**Architecture:** Beru and Igris are prompt-only subagents (`agents/*.md`, model sonnet, own context). The campaign's §3 (derive directions) dispatches **Beru** — who recalls prior campaigns via `kb.sh`/recall, inspects scope, and returns 2–4 concrete directions — replacing the Monarch's inline improvisation (with a graceful fallback to the `Directions:` arg / inline if Beru returns nothing). The campaign's §5 dispatches **Igris** to independently verify the best result (checkout/worktree the winning branch, re-run Verify, confirm the metric and that it isn't gamed) → accept/reject + reason, recorded in PROPOSAL.md. The Monarch skill roster is updated to list the now-present shadows. Additive to Phases 0–5 (on `main`); no shell scripts change.

**Tech Stack:** Claude Code agent markdown (frontmatter + body). Tests are structural (frontmatter + wiring greps) via the existing `tests/run.sh`, plus plugin-load.

## Global Constraints

- Agents are `agents/<name>.md` with valid YAML frontmatter: `name`, `description`, `tools`, `model: sonnet`, `color`, and (for the executor-like Igris that needs isolation) the worktree is created manually via `git worktree add` — **do NOT use native `isolation: worktree`** (PLAN §7; it broke in pre-`git init` sessions).
- **model: sonnet** for both (no ranks/ascension yet — that's the leveling phase; Opus-only-A+ rule means everyone is sonnet today). Note in each file that Igris ascends to opus once leveling lands.
- Beru is **read-mostly** (research): tools `Read, Grep, Glob, Bash` (Bash only for `kb.sh`/recall + scoping). Igris needs `Read, Bash, Grep, Glob` to checkout a branch in a throwaway worktree and re-run Verify. **Neither pushes/merges/deploys** (proposal-only, PLAN §9).
- **Safety:** Igris re-runs the campaign's `Verify` command — it MUST be the same command already safety-screened by the campaign; Igris does not invent new shell beyond worktree setup + the given Verify.
- Bash 3.2 for any inline snippets. Test files use `set -uo pipefail`. Additive — no Phase 0–5 regressions.
- Insert new `test_manifests.sh` checks before the single trailing `assert_done`. No placeholders.

## File Structure

```
agents/beru.md             # NEW — researcher: goal+metric -> directions (KB-informed)
agents/igris.md            # NEW — verifier: independent re-verify of the winning branch
skills/monarch/SKILL.md    # MODIFIED — roster lists Beru/Igris as present
commands/campaign.md       # MODIFIED — §3 dispatch Beru; §5 dispatch Igris (not "if present")
tests/test_manifests.sh    # MODIFIED — beru/igris frontmatter + campaign-dispatch checks
```

---

## Task 1: `agents/beru.md` — the Researcher shadow

**Files:**
- Create: `agents/beru.md`
- Modify: `tests/test_manifests.sh`

**Interfaces:**
- Agent `beru` (frontmatter: name, description, `tools: Read, Grep, Glob, Bash`, `model: sonnet`, `color`). Given a Goal + Metric + Direction + optional Scope, it: (1) recalls prior campaigns for this metric via `kb.sh search` (avoid re-proposing dead directions); (2) inspects the scope/codebase; (3) returns **2–4 concrete, distinct experiment directions** (one line each), each a falsifiable approach to move the metric — formatted as a `;`-separated list the campaign can feed to `allocate.sh add-arm`.

- [ ] **Step 1: Append beru checks to `tests/test_manifests.sh`** (before the final `assert_done`)

```bash
# --- Phase 6: Beru researcher ---
bru="$ROOT/agents/beru.md"
assert_eq "1" "$([ -f "$bru" ] && echo 1 || echo 0)" "beru.md exists"
brufm="$(sed -n '1,12p' "$bru")"
assert_contains "$brufm" "name: beru" "beru name"
assert_contains "$brufm" "model: sonnet" "beru runs sonnet"
assert_contains "$(cat "$bru")" "kb.sh" "beru recalls via kb.sh"
assert_contains "$(cat "$bru")" "Directions" "beru returns directions"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_manifests.sh` — Expected: FAIL (beru.md missing).

- [ ] **Step 3: Write `agents/beru.md`**

```markdown
---
name: beru
description: Researcher shadow (Ant King). Turns a goal + metric into 2–4 concrete, distinct, falsifiable experiment directions, informed by recall of past campaigns. Dispatched by the Monarch at campaign intake to seed the bandit's arms. Read-mostly; never edits code, pushes, or merges.
tools: Read, Grep, Glob, Bash
model: sonnet
color: red
---

You are Beru — Ant King, the Monarch's researcher. You address the Monarch as "my King". You devour
context and return sharp, distinct directions. You do NOT run experiments or edit code — you scout.

You receive: `Goal`, `Metric`, `Direction` (lower_is_better|higher_is_better), optional `Scope` (globs),
and the campaign `OutDir`.

## Protocol
1. **Recall first.** Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/kb.sh search "<metric / goal terms>"` (1–3
   focused keyword searches). Note any approach recorded as **dead** in a prior graveyard — do NOT propose it again.
2. **Scout the scope.** Use Read/Grep/Glob over the Scope (or the obvious files for the Goal) to ground
   your directions in what actually exists — not generic advice.
3. **Propose 2–4 directions.** Each must be: concrete (a specific change a soldier could try), distinct
   (genuinely different mechanism, not rewordings), and falsifiable against the Metric. Bias toward
   untried/promising angles from recall; avoid dead ones.

## Report (exactly this shape — the Monarch feeds it to the bandit)
```
Directions: <approach 1>; <approach 2>; <approach 3>
Rationale: <one line each: why this could move the metric, and any prior-art note from recall>
```
Keep it tight. Distinct, falsifiable, grounded. *for the King.*
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test_manifests.sh` then `bash tests/run.sh` — Expected: PASS; single trailing `assert_done`.

- [ ] **Step 5: Commit**

```bash
git add agents/beru.md tests/test_manifests.sh
git commit -m "feat: add beru researcher shadow (KB-informed direction proposal)"
```

---

## Task 2: `agents/igris.md` — the Verifier shadow

**Files:**
- Create: `agents/igris.md`
- Modify: `tests/test_manifests.sh`

**Interfaces:**
- Agent `igris` (frontmatter: name, description, `tools: Read, Bash, Grep, Glob`, `model: sonnet`, `color`). Given the winning `Branch`, the `Metric`/`Direction`/`Verify` command, and the claimed `BestMetric`, it: (1) creates a throwaway worktree of `Branch` via `git worktree add`; (2) re-runs the **given** `Verify` command there (no invented commands); (3) confirms the measured metric matches the claim and is in the improving direction vs baseline; (4) sanity-checks the change isn't trivially gaming the metric (reads the diff); (5) returns **accept/reject + reason**; (6) removes its worktree. Never pushes/merges.

- [ ] **Step 1: Append igris checks to `tests/test_manifests.sh`** (before the final `assert_done`)

```bash
# --- Phase 6: Igris verifier ---
ig="$ROOT/agents/igris.md"
assert_eq "1" "$([ -f "$ig" ] && echo 1 || echo 0)" "igris.md exists"
igfm="$(sed -n '1,12p' "$ig")"
assert_contains "$igfm" "name: igris" "igris name"
assert_contains "$igfm" "model: sonnet" "igris runs sonnet"
igb="$(cat "$ig")"
assert_contains "$igb" "git worktree add" "igris verifies in its own worktree"
assert_contains "$igb" "accept" "igris returns accept/reject verdict"
assert_eq "0" "$(grep -c 'isolation: worktree' "$ig" || true)" "igris uses manual worktree, not native isolation"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_manifests.sh` — Expected: FAIL (igris.md missing).

- [ ] **Step 3: Write `agents/igris.md`**

```markdown
---
name: igris
description: Verifier shadow (Knight Commander). Independently re-verifies a campaign's winning result before it is proposed — re-runs the Verify command on the winning branch in a throwaway worktree and judges whether the improvement is real and not gamed. Returns accept/reject with a reason. Never pushes or merges. (Ascends to opus once leveling lands.)
tools: Read, Bash, Grep, Glob
model: sonnet
color: cyan
---

You are Igris — Knight Commander. Silent, disciplined. You do not trust a claimed win until you have
seen it yourself. *kneels* when the verdict is delivered.

You receive: `Branch` (winning experiment branch), `Metric`, `Direction`, `Verify` (the exact command,
already safety-screened by the campaign), `BestMetric` (the claimed value), and `Baseline`.

## Protocol
1. **Isolate.** From the repo root:
   ```
   ROOT="$(git rev-parse --show-toplevel)"; WT="/tmp/shadow-verify-<Branch-sanitized>"
   git worktree remove -f "$WT" 2>/dev/null; true
   git worktree add "$WT" "<Branch>"
   cd "$WT"
   ```
2. **Re-verify.** Run the **given** `Verify` command (do not invent new shell beyond worktree setup).
   Extract the metric (pipe through `${CLAUDE_PLUGIN_ROOT}/scripts/metric.sh` if helpful).
3. **Judge.**
   - Does the re-measured metric match `BestMetric` (within reason) AND improve on `Baseline` in the
     correct `Direction`?
   - Read the diff (`git diff <baseline>..<Branch>`) — is the gain real, or is it gaming the metric
     (e.g. deleting the test, hardcoding the number, weakening the check)?
4. **Cleanup.** `cd "$ROOT" && git worktree remove -f "$WT"` (leave the branch).

## Report (exactly this shape)
```
Verdict: accept | reject
Measured: <metric>  (claimed <BestMetric>, baseline <Baseline>)
Reason: <one or two lines — confirmed real improvement, or what's wrong / how it's gamed>
```
Be skeptical. A reproduced, honest improvement earns *accept*. Anything you cannot reproduce, or that
games the metric, earns *reject*. *kneels.*
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test_manifests.sh` then `bash tests/run.sh` — Expected: PASS; single trailing `assert_done`.

- [ ] **Step 5: Commit**

```bash
git add agents/igris.md tests/test_manifests.sh
git commit -m "feat: add igris verifier shadow (independent re-verify in own worktree)"
```

---

## Task 3: Wire Beru + Igris into `/campaign` and the Monarch roster

**Files:**
- Modify: `commands/campaign.md`
- Modify: `skills/monarch/SKILL.md`
- Modify: `tests/test_manifests.sh`

**Interfaces:**
- `commands/campaign.md` §3: **dispatch the `beru` subagent** to derive directions (passing Goal/Metric/Direction/Scope/OutDir); use its `Directions:` output to `allocate.sh add-arm`. Fallback order unchanged: explicit `Directions:` arg wins if provided; else Beru; else Monarch inline (if Beru returns nothing).
- `commands/campaign.md` §5: **dispatch the `igris` subagent** to verify the best (passing Branch/Metric/Direction/Verify/BestMetric/Baseline); record the verdict in the report and pass it into the proposal context. Not "if present" — Igris now exists. (If Igris rejects, say so in the proposal and do not present it as verified.)
- `skills/monarch/SKILL.md`: roster table lists Beru (researcher) and Igris (verifier) as present; drop the "arrive in later phases" line (or narrow it to Soldiers).

- [ ] **Step 1: Append wiring checks to `tests/test_manifests.sh`** (before the final `assert_done`)

```bash
# --- Phase 6: Beru/Igris wired into campaign + roster ---
ccb6="$(cat "$ROOT/commands/campaign.md")"
assert_contains "$ccb6" "beru" "campaign dispatches beru for directions"
assert_contains "$ccb6" "igris" "campaign dispatches igris to verify"
mrb="$(cat "$ROOT/skills/monarch/SKILL.md")"
assert_contains "$mrb" "beru" "monarch roster lists beru"
assert_contains "$mrb" "igris" "monarch roster lists igris"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_manifests.sh` — Expected: FAIL (campaign/roster don't reference beru/igris yet).

- [ ] **Step 3: Edit `commands/campaign.md` §3** — replace the inline "propose 2–4 approaches" wording with a Beru dispatch:
```
- Derive the candidate directions (the bandit's arms):
  - If `Directions:` was given, use it.
  - Else **dispatch the `beru` subagent** with `Goal`, `Metric`, `Direction`, `Scope` (if any), and `OutDir`. Beru recalls prior campaigns and returns a `Directions: a; b; c` line — use it.
  - Else (Beru returns nothing) fall back to proposing 2–4 concrete directions yourself.
  Then `allocate.sh add-arm` each direction. (Beru already biases away from prior dead directions; the graveyard still applies.)
```

- [ ] **Step 4: Edit `commands/campaign.md` §5** — replace the "Optionally dispatch Igris (if present)" bullet:
```
- Independently verify the best: **dispatch the `igris` subagent** with the winning `Branch`, `Metric`, `Direction`, `Verify`, the claimed `BestMetric`, and `Baseline`. Record Igris's verdict (accept/reject + reason). If Igris rejects, do NOT present the result as verified — say so in the proposal.
- Write the proposal (never push or merge): `bash ${CLAUDE_PLUGIN_ROOT}/scripts/propose.sh write <state> <campaign>/PROPOSAL.md <winning experiment branch>`. Include Igris's verdict when you tell the user about PROPOSAL.md.
```

- [ ] **Step 5: Edit `skills/monarch/SKILL.md`** — extend the roster table and drop/narrow the "later phases" line:
```
| **Beru** | researcher (ant king) | recalls + proposes the experiment directions at campaign intake |
| **Igris** | verifier (knight) | independently re-verifies the winning result before it is proposed |
| **Tusk** | executor (tank) | runs one bounded experiment loop in an isolated worktree |
```
Change the trailing note to: `Soldiers (parallel recon swarm) and leveling arrive in later phases.`

- [ ] **Step 6: Run tests**

Run: `bash tests/test_manifests.sh` then `bash tests/run.sh` — Expected: PASS; single trailing `assert_done`.

- [ ] **Step 7: Commit**

```bash
git add commands/campaign.md skills/monarch/SKILL.md tests/test_manifests.sh
git commit -m "feat: wire beru (research) + igris (verify) into campaign; update monarch roster"
```

---

## Task 4: Suite + load + roster verification

**Files:** none (verification).

- [ ] **Step 1: Full suite** — `bash tests/run.sh`. Expected: all green.

- [ ] **Step 2: Plugin load + agent discovery** — `claude --plugin-dir "$(pwd)" --model haiku -p "Reply with exactly: LOADED"`. Expected LOADED, no manifest errors. If unavailable, DEFERRED.

- [ ] **Step 3: Agent roster check** — confirm all three specialists exist with valid frontmatter:
```bash
for a in beru igris tusk; do
  f="agents/$a.md"
  printf '%s: ' "$a"
  grep -q "name: $a" "$f" && grep -q "model: sonnet" "$f" && echo "ok" || echo "MISSING/BAD"
done
```
Expected: `beru: ok`, `igris: ok`, `tusk: ok`.

- [ ] **Step 4: No native isolation anywhere** (PLAN §7) —
```bash
grep -rln 'isolation: worktree' agents/ || echo "clean — no native isolation"
```
Expected: `clean`.

- [ ] **Step 5: Tag** — `git tag phase-6-specialists`.

---

## Self-Review

**Spec coverage:** Beru researcher (KB-informed directions) → Task 1; Igris verifier (independent re-verify in own worktree) → Task 2; both wired into campaign (Beru at §3, Igris at §5 — no longer "if present") + Monarch roster updated → Task 3; no native isolation (manual worktree) → Tasks 2,4; proposal-only/never-push preserved → Tasks 2,3. Additive; no Phase 0–5 regressions. Deferred (leveling phase): Igris ascends to opus, rank-gating, Soldiers swarm.

**Placeholder scan:** complete agent bodies + exact campaign/roster edits; no TODO-as-instruction. Names (Beru/Igris) are content.

**Interface consistency:** Beru's `Directions: a; b; c` output matches what campaign §3 feeds to `allocate.sh add-arm`; Igris's inputs (Branch/Metric/Direction/Verify/BestMetric/Baseline) match what campaign §5 passes; Igris reuses the already-safety-screened `Verify` (no new shell); both use manual `git worktree add` consistent with Tusk (PLAN §7).

## Notes for the executor
- Additive only — run the FULL suite after each task.
- Igris must reuse the campaign's given Verify command (already screened); it does not invent shell beyond worktree setup.
- model: sonnet for both (no ranks yet); note Igris→opus in the leveling phase.
- Insert new test_manifests checks before the single trailing `assert_done`.
- Never push/merge during implementation.
