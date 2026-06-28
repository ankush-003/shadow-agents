# Shadow Legion — Phase 5: Integration by Proposal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `gh pr create` integration step with a **proposal-only** flow — every verified campaign winner produces a reviewable `PROPOSAL.md` (winning approach, metric delta, the branch/commit to integrate, exact manual merge commands, dead-directions report). Drop `gh` as a hard dependency, and normalize the experiment `delta` sign so `results.tsv` and the bandit ledger agree.

**Architecture:** A new deterministic seam `scripts/propose.sh` writes `PROPOSAL.md` from the campaign state + winning branch. `commands/campaign.md` §5 calls it unconditionally (no `gh`, no remote needed); the army never pushes or merges — the human reads the proposal and integrates manually. `scripts/preflight.sh` moves `gh` from required to optional (informational). `agents/tusk.md` is made internally consistent on delta (signed: `final - baseline`). Additive to Phases 0–4 (on `main`).

**Tech Stack:** Bash 3.2 (macOS), `jq`. Tests via `tests/run.sh`.

## Global Constraints

- **Bash 3.2** (macOS): no associative arrays, no `${var^^}`, no `mapfile`. `jq` for JSON.
- Executable scripts: `#!/usr/bin/env bash` + `set -euo pipefail`; sourced libs do not; tests use `set -uo pipefail`.
- **Proposal-only integration**: the army NEVER pushes, merges, or runs `gh`. Integration = a written `PROPOSAL.md`; the human merges. (Replaces the former "PR-only" rule.)
- `gh` is **optional**, not required (no longer fatal in preflight).
- **Delta convention (normalized): signed `final - baseline`** everywhere — `results.tsv` and `orchestrator-state.json` agree. For `lower_is_better` an improvement is negative; for `higher_is_better` positive. (This matches what the bandit already records.)
- **Additive**: no regressions to Phase 0–4 contracts/tests.
- No placeholders.

## File Structure

```
scripts/propose.sh         # NEW — write PROPOSAL.md from state + winning branch
scripts/preflight.sh       # MODIFIED — gh becomes optional (informational), not required
commands/campaign.md       # MODIFIED — §5 proposal-only (drop gh pr create); rules/description
agents/tusk.md             # MODIFIED — delta logged as signed (final - baseline), internally consistent
tests/test_propose.sh      # NEW
tests/test_preflight.sh    # MODIFIED — gh no longer in the required-fail set
tests/test_manifests.sh    # MODIFIED — campaign proposal wiring checks
```

---

## Task 1: `scripts/propose.sh` — write PROPOSAL.md

**Files:**
- Create: `scripts/propose.sh`
- Test: `tests/test_propose.sh`

**Interfaces:**
- `propose.sh write <state_file> <out_file> <branch>` — reads `orchestrator-state.json`, computes the best arm (direction-aware) and writes a markdown `PROPOSAL.md` to `<out_file>` containing: a title, the winning approach (`desc`) + its `best` metric + `mean_delta`, the integration `branch`, exact manual merge commands (`git merge --ff-only <branch>` / `git cherry-pick`), a per-arm summary table, and a dead-directions section (from `dead`/`dead_reason`). Creates the parent dir. Errors (exit 1) if the state file is missing.

- [ ] **Step 1: Write the failing test `tests/test_propose.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
P="$DIR/../scripts/propose.sh"
A="$DIR/../scripts/allocate.sh"

sf="$(mktemp)"
"$A" init "$sf" lower_is_better 50 3
"$A" add-arm "$sf" a1 "Delete the TODO lines"
"$A" add-arm "$sf" a2 "Rewrite as DONE"
"$A" update "$sf" a1 0 -3 keep          # a1 best=0
"$A" update "$sf" a2 3 0 discard
"$A" update "$sf" a2 3 0 discard         # a2 stalls
"$A" mark-dead "$sf" a2 "no reduction across 2 tries"

out="$(mktemp -d)/PROPOSAL.md"
"$P" write "$sf" "$out" experiment/c1-a1-c0
body="$(cat "$out")"
assert_contains "$body" "Delete the TODO lines" "names winning approach"
assert_contains "$body" "experiment/c1-a1-c0" "names integration branch"
assert_contains "$body" "git merge" "gives manual merge command"
assert_contains "$body" "no reduction across 2 tries" "lists dead direction + reason"
assert_contains "$body" "PROPOSAL" "has a proposal title"

# missing state errors
"$P" write /no/such/state "$out" b 2>/dev/null; assert_exit 1 $? "missing state errors"
rm -rf "$(dirname "$out")" "$sf"
assert_done
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_propose.sh` — Expected: FAIL (script missing).

- [ ] **Step 3: Write `scripts/propose.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"

cmd="${1:-}"; [ "$cmd" = "write" ] || shadow_die "usage: propose.sh write <state> <out> <branch>"
sf="${2:-}"; out="${3:-}"; branch="${4:-}"
[ -f "$sf" ] || { echo "propose: state file not found: $sf" >&2; exit 1; }
[ -n "$out" ] && [ -n "$branch" ] || shadow_die "propose: out and branch required"
mkdir -p "$(dirname "$out")"

dir="$(jq -r '.direction' "$sf")"
# best arm: direction-aware over arms with a non-null best
best_id="$(jq -r --arg d "$dir" '
  [.arms[] | select(.best != null)] as $a
  | if ($a|length)==0 then ""
    elif $d=="lower_is_better" then ($a | sort_by(.best) | .[0].id)
    else ($a | sort_by(-.best) | .[0].id) end' "$sf")"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
  printf '# PROPOSAL — Shadow Legion campaign result\n\n'
  printf -- '- generated: %s\n' "$ts"
  printf -- '- metric direction: %s\n' "$dir"
  printf -- '- integration branch: `%s`\n\n' "$branch"

  if [ -n "$best_id" ]; then
    desc="$(jq -r --arg id "$best_id" '.arms[]|select(.id==$id).desc' "$sf")"
    best="$(jq -r --arg id "$best_id" '.arms[]|select(.id==$id).best' "$sf")"
    md="$(jq -r --arg id "$best_id" '.arms[]|select(.id==$id).mean_delta' "$sf")"
    printf '## Winning approach: %s\n\n' "$desc"
    printf -- '- best metric: **%s** (mean delta %s)\n\n' "$best" "$md"
  else
    printf '## No winning approach\n\nNo arm produced a measured improvement.\n\n'
  fi

  printf '## Integrate manually (the army never pushes or merges)\n\n'
  printf '```bash\n'
  printf 'git merge --ff-only %s        # fast-forward integrate the verified branch\n' "$branch"
  printf '# or, to take just the winning commit:\n'
  printf '# git cherry-pick <commit-from-results.tsv>\n'
  printf '```\n\n'

  printf '## All directions\n\n'
  printf '| arm | approach | attempts | best | mean_delta | dead | reason |\n'
  printf '|---|---|---|---|---|---|---|\n'
  jq -r '.arms[] | "| \(.id) | \(.desc) | \(.attempts) | \(.best // "-") | \(.mean_delta) | \(.dead) | \(.dead_reason // "") |"' "$sf"
  printf '\n'

  deadcount="$(jq -r '[.arms[]|select(.dead==true)]|length' "$sf")"
  if [ "$deadcount" -gt 0 ]; then
    printf '## Dead directions (do not retry)\n\n'
    jq -r '.arms[]|select(.dead==true)|"- **\(.desc)** — \(.dead_reason // "no reason recorded")"' "$sf"
    printf '\n'
  fi
} > "$out"
```

- [ ] **Step 4: Run tests to verify pass**

Run: `bash tests/test_propose.sh` then `bash tests/run.sh` — Expected: PASS, full suite green. `chmod +x scripts/propose.sh`.

- [ ] **Step 5: Commit**

```bash
git add scripts/propose.sh tests/test_propose.sh
git commit -m "feat: add propose.sh to write PROPOSAL.md (proposal-only integration)"
```

---

## Task 2: `preflight.sh` — `gh` optional, not required

**Files:**
- Modify: `scripts/preflight.sh`
- Modify: `tests/test_preflight.sh`

**Interfaces:**
- The required set becomes `git`, `jq`, `claude`, `memsearch`-or-`uvx` (NO `gh`). `gh` is checked separately and reported as informational (`[opt] gh present` / `[opt] gh absent — proposal-only integration`), never contributing to the failure exit code.

- [ ] **Step 1: Update `tests/test_preflight.sh`** — the existing test sources `preflight.sh` with `SHADOW_PREFLIGHT_LIB=1` and tests `check_tool`. Add an assertion that `gh` is not in the required-fail path. Before the final `assert_done`, add:

```bash
# gh is optional: a preflight run must NOT fail solely because gh is missing.
# Simulate by checking the required list excludes gh — run preflight with a PATH that has git/jq/claude/uvx but no gh.
# (Lightweight check: the script's required block must not reference gh with `|| rc=1`.)
pf="$DIR/../scripts/preflight.sh"
assert_eq "0" "$(grep -c 'check_tool gh gh .*rc=1' "$pf" || true)" "gh not in required-fail set"
assert_contains "$(cat "$pf")" "proposal-only" "gh reported as optional/proposal-only"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_preflight.sh` — Expected: FAIL (gh still required).

- [ ] **Step 3: Edit `scripts/preflight.sh`** — remove `check_tool gh gh || rc=1` from the required block; after the required checks, add an informational gh check that never sets `rc`:

```bash
rc=0
check_tool git git       || rc=1
check_tool jq jq         || rc=1
check_tool claude claude || rc=1
check_tool "memsearch (or uvx)" memsearch uvx || rc=1
# gh is OPTIONAL — integration is proposal-only; gh is not needed.
if command -v gh >/dev/null 2>&1; then echo "[opt] gh present"; else echo "[opt] gh absent — proposal-only integration"; fi
if [ "$rc" -ne 0 ]; then
  echo "Preflight failed. Install missing tools:" >&2
  echo "  memsearch:  uv tool install 'memsearch[onnx]'  (or: pipx install 'memsearch[onnx]')" >&2
  exit 1
fi
echo "All systems ready. ARISE."
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test_preflight.sh` then `bash tests/run.sh` — Expected: PASS, full suite green.

- [ ] **Step 5: Commit**

```bash
git add scripts/preflight.sh tests/test_preflight.sh
git commit -m "refactor: make gh optional in preflight (proposal-only integration)"
```

---

## Task 3: Wire proposal-only into `/campaign`; normalize tusk delta

**Files:**
- Modify: `commands/campaign.md`
- Modify: `agents/tusk.md`
- Modify: `tests/test_manifests.sh`

**Interfaces:**
- `commands/campaign.md`: §5 calls `propose.sh write <state> <campaign>/PROPOSAL.md <winning-branch>` (no `gh pr create`); description + rules say "proposal-only" and "never push/merge"; the report points the user at `PROPOSAL.md`.
- `agents/tusk.md`: the loop step and the report line both use **signed delta = `final - baseline`** (drop "in the improving direction"), so `results.tsv` agrees with the bandit ledger.
- New manifest checks: campaign body contains `propose.sh` and `PROPOSAL`; campaign body does NOT contain `gh pr create`.

- [ ] **Step 1: Append checks to `tests/test_manifests.sh`** (before the final `assert_done`)

```bash
# --- Phase 5: proposal-only integration ---
ccb5="$(cat "$ROOT/commands/campaign.md")"
assert_contains "$ccb5" "propose.sh" "campaign uses propose.sh"
assert_contains "$ccb5" "PROPOSAL" "campaign writes PROPOSAL.md"
assert_eq "0" "$(printf '%s' "$ccb5" | grep -c 'gh pr create' || true)" "campaign no longer uses gh pr create"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_manifests.sh` — Expected: FAIL (campaign still references gh pr create, no propose.sh).

- [ ] **Step 3: Edit `commands/campaign.md`**:
  - Frontmatter `description:` — change trailing "Reports learnings. PR-only." → "Reports learnings. Proposal-only (no auto-merge/push)."
  - §5 integration bullet — replace the `gh pr create` line with:
    ```
    - For the verified best, write a proposal (never push or merge): `bash ${CLAUDE_PLUGIN_ROOT}/scripts/propose.sh write <state> <campaign>/PROPOSAL.md <winning experiment branch>`. Tell the user the PROPOSAL.md path and that they review + integrate it manually.
    ```
  - Rules — change "Integration is PR-only, human-reviewed." → "Integration is proposal-only: write PROPOSAL.md; the human reviews and merges. Never push, merge, or run gh."

- [ ] **Step 4: Edit `agents/tusk.md`**:
  - Loop step (was "Run `Verify` → new metric; compute delta in the improving direction.") → "Run `Verify` → new metric; compute **signed delta = final − previous metric** (negative is an improvement for lower_is_better, positive for higher_is_better)."
  - Ensure the `results_append` guidance and the terse report both use `delta = final - baseline` (signed) consistently. (The report line already says `<final-baseline>` — keep it; just make the loop wording match.)

- [ ] **Step 5: Run tests**

Run: `bash tests/test_manifests.sh` then `bash tests/run.sh` — Expected: PASS; single trailing `assert_done`.

- [ ] **Step 6: Commit**

```bash
git add commands/campaign.md agents/tusk.md tests/test_manifests.sh
git commit -m "feat: proposal-only campaign integration; normalize signed delta in tusk"
```

---

## Task 4: Suite + load + proposal dry-run

**Files:** none (verification).

- [ ] **Step 1: Full suite** — `bash tests/run.sh`. Expected: all green (incl. test_propose.sh).

- [ ] **Step 2: Lint (if available)** — `command -v shellcheck >/dev/null && shellcheck scripts/*.sh tests/*.sh || echo "shellcheck not installed — skipping"`.

- [ ] **Step 3: Proposal dry-run (no agents):**
```bash
sf="$(mktemp)"; A=scripts/allocate.sh; P=scripts/propose.sh; out="$(mktemp -d)/PROPOSAL.md"
"$A" init "$sf" lower_is_better 50 3
"$A" add-arm "$sf" a1 "Delete the TODO lines"; "$A" add-arm "$sf" a2 "Rewrite as DONE"
"$A" update "$sf" a1 0 -3 keep
"$A" update "$sf" a2 3 0 discard; "$A" update "$sf" a2 3 0 discard
"$A" mark-dead "$sf" a2 "no reduction across 2 tries"
"$P" write "$sf" "$out" experiment/demo-a1-c0
echo "--- PROPOSAL.md ---"; cat "$out"
rm -f "$sf"; rm -rf "$(dirname "$out")"
```
Expected: PROPOSAL.md names the winning approach (a1, best 0), a `git merge --ff-only experiment/demo-a1-c0` command, the all-directions table, and a1's... sorry — a2's dead reason.

- [ ] **Step 4: preflight without gh is non-fatal** — confirm the required set excludes gh:
```bash
grep -n 'gh' scripts/preflight.sh
```
Expected: gh appears only in the optional/informational line, not in a `|| rc=1` required check.

- [ ] **Step 5: Plugin load** — `claude --plugin-dir "$(pwd)" --model haiku -p "Reply with exactly: LOADED"`. Expected LOADED. If unavailable, DEFERRED.

- [ ] **Step 6: Tag** — `git tag phase-5-proposal`.

---

## Self-Review

**Spec coverage:** proposal artifact (`propose.sh` → PROPOSAL.md) → Task 1; gh optional → Task 2; campaign proposal-only (drop gh pr create) → Task 3; signed-delta normalization (results.tsv ↔ ledger agree) → Task 3; never push/merge preserved → Task 3 rules. Additive; no Phase 0–4 regressions.

**Placeholder scan:** complete code in shell steps; prose steps name exact edits. "PROPOSAL"/"gh" are literal.

**Interface consistency:** `propose.sh write <state> <out> <branch>` signature matches Task 1 def, Task 3 campaign call, and Task 4 dry-run; the manifest checks (Task 3) assert exactly the campaign edits; preflight required-set change (Task 2) matches its test.

## Notes for the executor
- Additive only — run the FULL suite after each task.
- Insert new test_manifests checks before the single trailing `assert_done`.
- The army must never push/merge/`gh`; proposal is the only integration output.
- Don't push or open PRs during implementation.
