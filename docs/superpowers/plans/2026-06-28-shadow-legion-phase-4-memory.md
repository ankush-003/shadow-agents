# Shadow Legion — Phase 4: Memory (KB + Recall) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the army memory of past experiments — a knowledge base over `.shadow` (exp-notes, handoffs, results, graveyard) searchable via memsearch (preferred) or a grep fallback, plus a `recall` skill and wiring so shadows check "have we tried this? / what worked for metric X?" *before* experimenting, stopping repeats and surfacing prior learnings.

**Architecture:** `scripts/kb.sh` is the deterministic memory seam: `search` prefers the `memsearch` CLI (semantic, over a per-project collection) and falls back to `grep` over the `.shadow` markdown (the source of truth) when memsearch is absent — so it always works and is testable without Milvus. A `recall` skill (`context: fork`) runs `kb.sh search` in an isolated subagent and returns a curated summary. Tusk's RECALL step and the campaign intake use it. Builds on Phases 0–3 (on `main`).

**Tech Stack:** Bash 3.2 (macOS), `jq`, optional `memsearch` CLI (already installed; ONNX + Milvus Lite, no server). Tests via `tests/run.sh`, forcing the grep fallback for determinism.

## Global Constraints

- **Bash 3.2** (macOS): no associative arrays, no `${var^^}`, no `mapfile`.
- Executable scripts: `#!/usr/bin/env bash` + `set -euo pipefail`; sourced libs do not; tests use `set -uo pipefail`.
- **memsearch is the preferred path; grep is the always-available fallback.** `SHADOW_KB_NOMEMSEARCH=1` forces the fallback (used by tests for determinism). The markdown under `.shadow` is the source of truth — recall must work with grep alone.
- **Additive only**: no regressions to Phase 0–3 contracts/tests.
- `recall` skill uses `context: fork` (isolated subagent) + `allowed-tools: Bash`.
- No placeholders; every shipped file complete.

## File Structure

```
scripts/kb.sh              # NEW — memory seam: search (memsearch|grep) + index
skills/recall/SKILL.md     # NEW — context:fork recall over the KB
agents/tusk.md             # MODIFIED — RECALL step also runs kb.sh search
commands/campaign.md       # MODIFIED — intake surfaces prior knowledge via recall/kb
tests/test_kb.sh           # NEW
tests/test_manifests.sh    # MODIFIED — recall skill + kb wiring checks
```

---

## Task 1: `scripts/kb.sh` — memory seam (memsearch + grep fallback)

**Files:**
- Create: `scripts/kb.sh`
- Test: `tests/test_kb.sh`

**Interfaces:**
- `kb.sh search <query> [root]` — root defaults to `${CLAUDE_PROJECT_DIR:-git toplevel|pwd}`. If a memsearch CLI is available (and `SHADOW_KB_NOMEMSEARCH` unset) it runs `memsearch search` over the per-project collection and prints hits; on empty/no-memsearch it falls back to `grep -rinE` over `<root>/.shadow` markdown/tsv and prints `file:line:match` (capped). No matches → empty output, exit 0.
- `kb.sh index [root]` — if memsearch available, indexes `<root>/.shadow` into the per-project collection; otherwise prints a "grep fallback active" notice and exits 0.

- [ ] **Step 1: Write the failing test `tests/test_kb.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
K="$DIR/../scripts/kb.sh"

root="$(mktemp -d)"; mkdir -p "$root/.shadow/experiments/exp-1"
printf '## Iteration 1\nTried GeLU activation -> regressed bpb. Discarded.\n' \
  > "$root/.shadow/experiments/exp-1/exp-notes.md"

# grep fallback (forced) finds a known term + its context line
out="$(SHADOW_KB_NOMEMSEARCH=1 "$K" search "GeLU" "$root")"
assert_contains "$out" "GeLU" "kb search finds known term"
assert_contains "$out" "regressed" "kb search returns context line"

# miss returns empty
miss="$(SHADOW_KB_NOMEMSEARCH=1 "$K" search "quantummonad" "$root")"
assert_eq "" "$miss" "kb search empty on miss"

# search on a root with no .shadow is safe/empty
empty_root="$(mktemp -d)"
none="$(SHADOW_KB_NOMEMSEARCH=1 "$K" search "anything" "$empty_root")"
assert_eq "" "$none" "kb search empty when no .shadow"

# index degrades gracefully without memsearch
idx="$(SHADOW_KB_NOMEMSEARCH=1 "$K" index "$root")"
assert_contains "$idx" "fallback" "index degrades gracefully without memsearch"

rm -rf "$root" "$empty_root"
assert_done
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_kb.sh` — Expected: FAIL (script missing).

- [ ] **Step 3: Write `scripts/kb.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"

cmd="${1:-}"; [ -n "$cmd" ] || shadow_die "usage: kb.sh search <query> [root] | index [root]"
shift

_root(){ printf '%s' "${1:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}"; }
_col(){ printf 'sl_%s' "$(basename "$1" | tr -c 'A-Za-z0-9' '_')"; }
_ms(){
  [ -n "${SHADOW_KB_NOMEMSEARCH:-}" ] && { printf ''; return 0; }
  if command -v memsearch >/dev/null 2>&1; then printf 'memsearch'
  elif command -v uvx >/dev/null 2>&1; then printf 'uvx --from memsearch[onnx] memsearch'
  else printf ''; fi
}

case "$cmd" in
  search)
    q="${1:-}"; [ -n "$q" ] || shadow_die "search: query required"
    root="$(_root "${2:-}")"; kbdir="$root/.shadow"
    ms="$(_ms)"
    if [ -n "$ms" ]; then
      out="$($ms search "$q" --collection "$(_col "$root")" --top-k 5 2>/dev/null || true)"
      [ -n "$out" ] && { printf '%s\n' "$out"; exit 0; }
    fi
    [ -d "$kbdir" ] || exit 0
    grep -rinE "$q" "$kbdir" --include='*.md' --include='*.tsv' 2>/dev/null | head -20 || true
    ;;
  index)
    root="$(_root "${1:-}")"; ms="$(_ms)"
    [ -n "$ms" ] || { echo "kb: memsearch unavailable — grep fallback active (no index needed)"; exit 0; }
    [ -d "$root/.shadow" ] || { echo "kb: nothing to index"; exit 0; }
    if $ms index "$root/.shadow" --collection "$(_col "$root")" >/dev/null 2>&1; then
      echo "kb: indexed $root/.shadow"
    else
      echo "kb: index skipped (memsearch error) — grep fallback active"
    fi
    ;;
  *) shadow_die "unknown subcommand: $cmd" ;;
esac
```

- [ ] **Step 4: Run tests to verify pass**

Run: `bash tests/test_kb.sh` then `bash tests/run.sh` — Expected: PASS, full suite green. `chmod +x scripts/kb.sh`.

- [ ] **Step 5: Commit**

```bash
git add scripts/kb.sh tests/test_kb.sh
git commit -m "feat: add kb.sh memory seam (memsearch-preferred, grep fallback)"
```

---

## Task 2: `recall` skill

**Files:**
- Create: `skills/recall/SKILL.md`
- Modify: `tests/test_manifests.sh`

**Interfaces:**
- A `recall` skill (`context: fork`, `allowed-tools: Bash`) that, given a question in `$ARGUMENTS`, runs `kb.sh search` for the key terms and returns a curated summary of relevant prior experiments (kept/discarded/dead + why), or "No relevant prior experiments found."

- [ ] **Step 1: Append recall checks to `tests/test_manifests.sh`** (before the final `assert_done`)

```bash
# --- Phase 4: recall skill ---
rk="$ROOT/skills/recall/SKILL.md"
assert_eq "1" "$([ -f "$rk" ] && echo 1 || echo 0)" "recall SKILL.md exists"
rkfm="$(sed -n '1,8p' "$rk")"
assert_contains "$rkfm" "name: recall" "recall frontmatter name"
assert_contains "$rkfm" "context: fork" "recall runs in fork context"
assert_contains "$(cat "$rk")" "kb.sh" "recall uses kb.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_manifests.sh` — Expected: FAIL (recall skill missing).

- [ ] **Step 3: Write `skills/recall/SKILL.md`**

```markdown
---
name: recall
description: Recall relevant past experiments and learnings from the Shadow Legion knowledge base (.shadow). Use before starting an experiment or campaign to check "have we tried this?" or "what worked / failed for metric X?". Searches prior exp-notes, handoffs, results, and the graveyard of dead directions.
context: fork
allowed-tools: Bash
---

You are the Legion's archivist. Search the experiment memory and return only what changes what to try next.

## Task
Recall memory relevant to: $ARGUMENTS

## Steps
1. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/kb.sh search "<key term>"` for the core terms of the question — the metric name, an approach, or a technique. Try 1–3 focused keyword searches (one term each works best with the grep fallback).
2. The search already covers the `graveyard.md` of dead directions — note any approach recorded there as dead (with its reason) so it is NOT retried.
3. Evaluate the hits; discard generic or irrelevant ones.
4. Return a concise summary, with source file references:
   - **Tried & kept:** approaches that improved the metric
   - **Tried & failed/dead:** approaches that regressed or were pruned, and WHY
   - **Untried angles** worth considering
   If nothing relevant is found, say exactly: "No relevant prior experiments found."

Keep it short — only decision-changing memory, not a transcript.
```

- [ ] **Step 4: Run tests**

Run: `bash tests/test_manifests.sh` then `bash tests/run.sh` — Expected: PASS; single trailing `assert_done`.

- [ ] **Step 5: Commit**

```bash
git add skills/recall/SKILL.md tests/test_manifests.sh
git commit -m "feat: add recall skill (context:fork) over the KB"
```

---

## Task 3: Wire recall/KB into Tusk + campaign

**Files:**
- Modify: `agents/tusk.md`
- Modify: `commands/campaign.md`
- Modify: `tests/test_manifests.sh`

**Interfaces:**
- Consumes: `kb.sh search`, the `recall` skill.
- Produces: Tusk's RECALL step also runs `kb.sh search` for its metric/approach (beyond just reading the graveyard) to avoid repeats and reuse prior learnings; campaign intake invokes recall (or `kb.sh search`) on the goal/metric to seed/avoid directions, and indexes the KB (`kb.sh index`) so memsearch (if present) stays current.

- [ ] **Step 1: Append wiring checks to `tests/test_manifests.sh`** (before the final `assert_done`)

```bash
# --- Phase 4: KB wiring ---
assert_contains "$(cat "$ROOT/agents/tusk.md")" "kb.sh" "tusk RECALL uses kb.sh"
ccb4="$(cat "$ROOT/commands/campaign.md")"
assert_contains "$ccb4" "kb.sh" "campaign uses kb.sh (recall/index)"
assert_contains "$ccb4" "recall" "campaign invokes recall at intake"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_manifests.sh` — Expected: FAIL.

- [ ] **Step 3: Edit `agents/tusk.md`** — extend the RECALL note (the line added in Phase 3 about graveyard.md) to also search the KB:
```
- RECALL: before your first change, run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/kb.sh search "<metric or approach>"` to see what past shadows tried (kept/failed) and read `OutDir/../graveyard.md`; do NOT repeat a dead approach — pick a different angle.
```

- [ ] **Step 4: Edit `commands/campaign.md`** — in the intake/derive-directions step (§3), add: before deriving directions, gather prior knowledge:
```
- Index + recall prior knowledge: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/kb.sh index` (keeps the memsearch collection current; no-op without memsearch), then use the `recall` skill (or `kb.sh search "<metric/goal terms>"`) to learn what past campaigns tried for this metric. Bias the derived directions toward untried/promising angles and AWAY from anything already recorded dead in a prior graveyard.
```

- [ ] **Step 5: Run tests**

Run: `bash tests/test_manifests.sh` then `bash tests/run.sh` — Expected: PASS; single trailing `assert_done`.

- [ ] **Step 6: Commit**

```bash
git add agents/tusk.md commands/campaign.md tests/test_manifests.sh
git commit -m "feat: wire KB recall into tusk RECALL and campaign intake"
```

---

## Task 4: Suite + load + KB dry-run

**Files:** none (verification).

- [ ] **Step 1: Full suite** — `bash tests/run.sh`. Expected: all green (incl. test_kb.sh).

- [ ] **Step 2: Lint (if available)** — `command -v shellcheck >/dev/null && shellcheck scripts/*.sh tests/*.sh || echo "shellcheck not installed — skipping"`.

- [ ] **Step 3: KB dry-run (grep fallback, no memsearch needed):**
```bash
root="$(mktemp -d)"; mkdir -p "$root/.shadow/experiments/e1"
printf 'tried larger batch -> improved bpb (keep)\nGeLU -> regressed (discard)\n' > "$root/.shadow/experiments/e1/exp-notes.md"
echo "hit: $(SHADOW_KB_NOMEMSEARCH=1 scripts/kb.sh search 'batch' "$root")"
echo "miss: [$(SHADOW_KB_NOMEMSEARCH=1 scripts/kb.sh search 'zzzznope' "$root")]"
echo "index: $(SHADOW_KB_NOMEMSEARCH=1 scripts/kb.sh index "$root")"
rm -rf "$root"
```
Expected: hit shows the batch line, miss is empty `[]`, index prints the fallback notice.

- [ ] **Step 4: memsearch presence note** — `command -v memsearch >/dev/null && echo "memsearch present — semantic path active" || echo "memsearch absent — grep fallback active"`. Either is acceptable (report which).

- [ ] **Step 5: Plugin load** — `claude --plugin-dir "$(pwd)" --model haiku -p "Reply with exactly: LOADED"`. Expected LOADED; recall skill discoverable. If unavailable, DEFERRED.

- [ ] **Step 6: Tag** — `git tag phase-4-memory`.

---

## Self-Review

**Spec coverage:** KB over `.shadow` markdown (source of truth) → Task 1; memsearch-preferred + grep fallback (works without Milvus, testable) → Task 1; `recall` skill `context:fork` → Task 2; shadows check "tried this?/what worked?" before experimenting → Task 3 (tusk RECALL + campaign intake); index keeps memsearch current → Task 3. Additive; no Phase 0–3 regressions.

**Placeholder scan:** complete code in shell steps; prose steps name exact commands. "GeLU"/"batch" are fixture data.

**Interface consistency:** `kb.sh search/index` signatures match between Task 1, the recall skill (Task 2), and the wiring (Task 3) + dry-run (Task 4); `SHADOW_KB_NOMEMSEARCH` forces fallback consistently in tests and dry-run; recall frontmatter `context: fork` matches the manifest check.

## Notes for the executor
- Force the grep fallback (`SHADOW_KB_NOMEMSEARCH=1`) in tests — never depend on memsearch/Milvus being configured in CI.
- Additive only; run the FULL suite after Task 1.
- Insert new test_manifests checks before the single trailing `assert_done`.
- Don't push or open PRs during implementation.
