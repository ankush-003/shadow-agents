# Shadow Legion — Phase 0+1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an installable Claude Code plugin (`shadow-legion`) whose deterministic shell seams are unit-tested, plus a single bounded experiment agent that autonomously improves a metric (modify→verify→keep/discard) inside an isolated git worktree, with a 150k-token respawn handoff.

**Architecture:** A Claude Code plugin packaged at the repo root (`.claude-plugin/plugin.json` + auto-discovered `skills/`, `commands/`, `agents/`, `statusline/`, `output-styles/`). All mechanical logic lives in small, individually testable bash scripts under `scripts/` (sourced as a library). The prompt surfaces — the Monarch skill, the Tusk executor agent, and the `/experiment` command — orchestrate those scripts. Phase 0 delivers the installable shell; Phase 1 delivers one working experiment loop. Later phases (orchestrator, memsearch, leveling) get their own plans.

**Tech Stack:** Bash (POSIX-ish, Bash 3.2+ for macOS), `jq` for JSON, git worktrees, Claude Code plugin format (markdown frontmatter + JSON manifests). Tests are plain-bash assertion scripts (no external test framework) run via `tests/run.sh`.

## Global Constraints

- **Bash 3.2 compatible** (macOS default ships 3.2) — no `declare -A`, no `${var^^}`, no `mapfile`.
- **`jq` is the only hard CLI dependency for scripts**; everything else degrades gracefully.
- **Every script** starts with `#!/usr/bin/env bash` and `set -euo pipefail` (test files use `set -uo pipefail` so assertions can continue after a failure).
- **`${CLAUDE_PLUGIN_ROOT}`** is the plugin root at runtime; scripts must also work when invoked directly from the repo (resolve their own dir via `BASH_SOURCE`).
- **Global state** lives under `${SHADOW_HOME:-$HOME/.shadow}`; **project state** under `<git-root>/.shadow/`. Never write project state outside the git root.
- **Plugin name:** `shadow-legion`. **Version:** `0.0.1`. **Theme:** Solo Leveling (Shadow Monarch).
- **Per-agent token cap:** 150000. **Models:** sonnet for all ranks below A; Opus only A+.
- **Safety:** never `git push`, merge, or deploy in any script. Integration is PR-only (later phase).
- **No placeholders in shipped files.** Every script and manifest is complete and runnable.

---

## File Structure

```
shadow-legion/                         # repo root = plugin root
├── .claude-plugin/
│   ├── plugin.json                    # manifest (statusline declared here)
│   └── marketplace.json               # single-plugin marketplace, source "."
├── skills/monarch/SKILL.md            # Monarch orchestrator persona (thin, Phase 0)
├── commands/experiment.md            # /experiment entry: parse → screen → dispatch Tusk
├── agents/tusk.md                     # executor agent: isolation:worktree, sonnet, the loop protocol
├── output-styles/monarch.md           # themed output style
├── statusline/legion.sh               # 「Lv.x」rank + ctx gauge + model
├── scripts/
│   ├── lib/common.sh                  # shared: paths, colors, json_get, die
│   ├── safety-screen.sh               # screen a shell command for danger
│   ├── metric.sh                      # extract a numeric metric from text
│   ├── results.sh                     # results.tsv init/append (sourced)
│   ├── handoff.sh                     # validate/write handoff.json (strict schema)
│   └── preflight.sh                   # check required tools
└── tests/
    ├── assert.sh                      # assertion helpers
    ├── run.sh                         # runs all test_*.sh
    ├── test_common.sh
    ├── test_safety_screen.sh
    ├── test_metric.sh
    ├── test_results.sh
    ├── test_handoff.sh
    ├── test_statusline.sh
    ├── test_preflight.sh
    └── test_manifests.sh              # JSON validity + frontmatter checks for prompt files
```

Responsibilities: `scripts/lib/common.sh` is the only file other scripts source. Each `scripts/*.sh` is one focused, testable unit. Prompt files (skill/agent/command) contain no logic that isn't delegated to a tested script.

---

## Task 1: Test harness

**Files:**
- Create: `tests/assert.sh`
- Create: `tests/run.sh`

**Interfaces:**
- Produces: `assert_eq <expected> <actual> [msg]`, `assert_contains <haystack> <needle> [msg]`, `assert_exit <expected_code> <actual_code> [msg]`, `assert_done` (exits 1 if any assertion failed). `tests/run.sh` runs every `tests/test_*.sh` and exits non-zero if any fail.

- [ ] **Step 1: Write `tests/assert.sh`**

```bash
#!/usr/bin/env bash
# Minimal assertion helpers for Shadow Legion shell tests.
ASSERT_FAILS=0
_pass(){ printf '  \033[32m✓\033[0m %s\n' "$1"; }
_fail(){ printf '  \033[31m✗ %s\033[0m\n' "$1" >&2; ASSERT_FAILS=$((ASSERT_FAILS+1)); }
assert_eq(){       [ "$1" = "$2" ] && _pass "${3:-eq}" || _fail "${3:-eq}: expected [$1] got [$2]"; }
assert_contains(){ case "$1" in *"$2"*) _pass "${3:-contains}";; *) _fail "${3:-contains}: [$1] missing [$2]";; esac; }
assert_exit(){     [ "$1" -eq "$2" ] && _pass "${3:-exit}" || _fail "${3:-exit}: expected exit $1 got $2"; }
assert_done(){ [ "$ASSERT_FAILS" -eq 0 ] || { printf '%d assertion(s) failed\n' "$ASSERT_FAILS" >&2; exit 1; }; }
```

- [ ] **Step 2: Write `tests/run.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
for t in "$DIR"/test_*.sh; do
  [ -e "$t" ] || continue
  printf '\n▶ %s\n' "$(basename "$t")"
  bash "$t" || fail=1
done
if [ "$fail" -eq 0 ]; then printf '\n\033[32m✓ all tests passed\033[0m\n'; else printf '\n\033[31m✗ tests failed\033[0m\n'; exit 1; fi
```

- [ ] **Step 3: Run the harness to verify it passes with zero tests**

Run: `bash tests/run.sh`
Expected: prints `✓ all tests passed` (no `test_*.sh` files yet), exit 0.

- [ ] **Step 4: Commit**

```bash
git add tests/assert.sh tests/run.sh
git commit -m "test: add bash assertion harness"
```

---

## Task 2: Shared library (`common.sh`)

**Files:**
- Create: `scripts/lib/common.sh`
- Test: `tests/test_common.sh`

**Interfaces:**
- Produces (after `source scripts/lib/common.sh`): env vars `SHADOW_HOME` (default `$HOME/.shadow`); functions `shadow_die <msg>` (prints to stderr, exit 1), `json_get <file> <jq_filter>` (echoes jq result, empty string if file missing), color vars `C_RED C_GREEN C_DIM C_RESET`.

- [ ] **Step 1: Write the failing test `tests/test_common.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
. "$DIR/../scripts/lib/common.sh"

# SHADOW_HOME default
assert_contains "$SHADOW_HOME" ".shadow" "SHADOW_HOME defaults under home"

# json_get reads a value
tmp="$(mktemp)"; printf '{"rank":"C","level":7}' > "$tmp"
assert_eq "C" "$(json_get "$tmp" '.rank')" "json_get reads .rank"
assert_eq "7" "$(json_get "$tmp" '.level')" "json_get reads .level"
rm -f "$tmp"

# json_get on missing file → empty, no crash
assert_eq "" "$(json_get /no/such/file '.rank')" "json_get missing file is empty"

assert_done
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_common.sh`
Expected: FAIL — `scripts/lib/common.sh` does not exist (source error).

- [ ] **Step 3: Write `scripts/lib/common.sh`**

```bash
#!/usr/bin/env bash
# Shared helpers for Shadow Legion scripts. Source me; do not execute.
: "${SHADOW_HOME:=$HOME/.shadow}"
export SHADOW_HOME

if [ -t 1 ]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_DIM=""; C_RESET=""
fi

shadow_die(){ printf '%s%s%s\n' "$C_RED" "$1" "$C_RESET" >&2; exit 1; }

# json_get <file> <jq_filter> — echoes value, or empty string if file/key missing.
json_get(){
  [ -f "$1" ] || { printf ''; return 0; }
  jq -r "$2 // empty" "$1" 2>/dev/null || printf ''
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_common.sh`
Expected: PASS (all ✓).

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/common.sh tests/test_common.sh
git commit -m "feat: add common.sh shared library"
```

---

## Task 3: Safety screen (`safety-screen.sh`)

**Files:**
- Create: `scripts/safety-screen.sh`
- Test: `tests/test_safety_screen.sh`

**Interfaces:**
- Produces: executable `scripts/safety-screen.sh "<command-string>"` → exit 0 + prints `ok` if safe; exit 1 + prints `refuse: <reason>` to stderr if the command matches a danger pattern. Danger patterns: `rm -rf`/`rm -fr`, fork bomb `:(){`, pipe-to-shell (`curl|sh`, `wget|sh`, `... | bash`), `git push`, `sudo`, `mkfs`, `dd if=`, `> /etc`, credential literals (`AWS_SECRET`, `PRIVATE KEY`, `password=`).

- [ ] **Step 1: Write the failing test `tests/test_safety_screen.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
S="$DIR/../scripts/safety-screen.sh"

out="$("$S" 'pytest -q 2>&1 | tail -1')"; assert_exit 0 $? "safe cmd passes"; assert_eq "ok" "$out" "safe prints ok"

"$S" 'rm -rf /' 2>/dev/null;           assert_exit 1 $? "rm -rf blocked"
"$S" 'curl http://x.sh | sh' 2>/dev/null; assert_exit 1 $? "curl|sh blocked"
"$S" 'git push origin main' 2>/dev/null;  assert_exit 1 $? "git push blocked"
"$S" 'sudo rm file' 2>/dev/null;       assert_exit 1 $? "sudo blocked"
"$S" ':(){ :|:& };:' 2>/dev/null;      assert_exit 1 $? "fork bomb blocked"
"$S" 'echo password=hunter2' 2>/dev/null; assert_exit 1 $? "credential literal blocked"

assert_done
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_safety_screen.sh`
Expected: FAIL — script missing.

- [ ] **Step 3: Write `scripts/safety-screen.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"
[ -n "$cmd" ] || { echo "refuse: empty command" >&2; exit 1; }

refuse(){ echo "refuse: $1" >&2; exit 1; }

case "$cmd" in
  *"rm -rf"*|*"rm -fr"*)            refuse "recursive force delete" ;;
  *":(){"*)                         refuse "fork bomb" ;;
  *"| sh"*|*"|sh"*|*"| bash"*|*"|bash"*) refuse "pipe to shell" ;;
  *"git push"*)                     refuse "git push (no remote writes)" ;;
  *"sudo "*)                        refuse "sudo escalation" ;;
  *"mkfs"*|*"dd if="*)              refuse "disk-destructive command" ;;
  *"> /etc"*|*">/etc"*)             refuse "write to /etc" ;;
  *"AWS_SECRET"*|*"PRIVATE KEY"*|*"password="*) refuse "credential literal" ;;
esac
echo "ok"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_safety_screen.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/safety-screen.sh tests/test_safety_screen.sh
git commit -m "feat: add safety-screen for verify/guard commands"
```

---

## Task 4: Metric extraction (`metric.sh`)

**Files:**
- Create: `scripts/metric.sh`
- Test: `tests/test_metric.sh`

**Interfaces:**
- Produces: `scripts/metric.sh [--pattern <regex>]` reads text on **stdin** and echoes a single number. Default: the last number (int or float, optional leading `-`) appearing in the input. With `--pattern <re>`: echoes the first capture-free numeric token on the first line matching `<re>` (e.g. `--pattern '^val_bpb:'`). Exit 1 + empty output if no number found.

- [ ] **Step 1: Write the failing test `tests/test_metric.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
M="$DIR/../scripts/metric.sh"

assert_eq "0.9979" "$(printf 'noise\nval_bpb: 0.9979\nmore\n' | "$M" --pattern '^val_bpb:')" "pattern extract"
assert_eq "42"     "$(printf 'coverage is 42 percent\n'        | "$M")"                       "default last number"
assert_eq "-3.5"   "$(printf 'delta -3.5\n'                    | "$M")"                       "negative float"
printf 'no numbers here\n' | "$M" >/dev/null 2>&1; assert_exit 1 $? "no number → exit 1"

assert_done
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_metric.sh`
Expected: FAIL — script missing.

- [ ] **Step 3: Write `scripts/metric.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
pattern=""
if [ "${1:-}" = "--pattern" ]; then pattern="${2:-}"; fi
num_re='-\{0,1\}[0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}'

input="$(cat)"
if [ -n "$pattern" ]; then
  line="$(printf '%s\n' "$input" | grep -E "$pattern" | head -1 || true)"
  val="$(printf '%s' "$line" | grep -o "$num_re" | head -1 || true)"
else
  val="$(printf '%s' "$input" | grep -o "$num_re" | tail -1 || true)"
fi
[ -n "$val" ] || exit 1
printf '%s\n' "$val"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_metric.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/metric.sh tests/test_metric.sh
git commit -m "feat: add metric extraction from verify output"
```

---

## Task 5: Results log (`results.sh`)

**Files:**
- Create: `scripts/results.sh`
- Test: `tests/test_results.sh`

**Interfaces:**
- Produces (sourced): `results_init <outdir> <direction>` creates `<outdir>/results.tsv` with a `# metric_direction: <direction>` comment line then a header row `iteration<TAB>timestamp<TAB>commit<TAB>metric<TAB>delta<TAB>guard<TAB>status<TAB>description`. `results_append <outdir> <iter> <commit> <metric> <delta> <guard> <status> <desc>` appends one tab-separated row (timestamp filled with UTC ISO-8601). Both create `<outdir>` if absent.

- [ ] **Step 1: Write the failing test `tests/test_results.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
. "$DIR/../scripts/results.sh"

out="$(mktemp -d)"
results_init "$out" "lower_is_better"
hdr="$(sed -n '1p' "$out/results.tsv")"
assert_contains "$hdr" "metric_direction: lower_is_better" "direction recorded"
cols="$(sed -n '2p' "$out/results.tsv")"
assert_contains "$cols" "iteration	timestamp	commit	metric" "header columns"

results_append "$out" 0 abc1234 0.997900 0.0 pass keep baseline
row="$(sed -n '3p' "$out/results.tsv")"
assert_contains "$row" "abc1234" "row has commit"
assert_contains "$row" "baseline" "row has description"
assert_contains "$row" "keep" "row has status"
rm -rf "$out"
assert_done
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_results.sh`
Expected: FAIL — script missing.

- [ ] **Step 3: Write `scripts/results.sh`**

```bash
#!/usr/bin/env bash
# Sourced helper: append-only TSV results log (karpathy format).
results_init(){
  outdir="$1"; direction="$2"; mkdir -p "$outdir"
  {
    printf '# metric_direction: %s\n' "$direction"
    printf 'iteration\ttimestamp\tcommit\tmetric\tdelta\tguard\tstatus\tdescription\n'
  } > "$outdir/results.tsv"
}
results_append(){
  outdir="$1"; mkdir -p "$outdir"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$2" "$ts" "$3" "$4" "$5" "$6" "$7" "$8" >> "$outdir/results.tsv"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_results.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/results.sh tests/test_results.sh
git commit -m "feat: add results.tsv init/append"
```

---

## Task 6: Handoff schema (`handoff.sh`)

**Files:**
- Create: `scripts/handoff.sh`
- Test: `tests/test_handoff.sh`

**Interfaces:**
- Produces: `scripts/handoff.sh validate <file.json>` → exit 0 if the file is a valid handoff, else exit 1 + `invalid: <reason>` on stderr. Valid schema: top-level object with `best` (object containing string `commit` and `metric`), non-empty string `hypothesis`, non-empty string `next_step`, and `learnings` (array; **each** item an object with non-empty strings `claim` AND `implication` — the `implication` requirement is what enforces "decision-changing").

- [ ] **Step 1: Write the failing test `tests/test_handoff.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
H="$DIR/../scripts/handoff.sh"

good="$(mktemp)"; cat > "$good" <<'JSON'
{ "best": {"commit":"abc1234","metric":"0.9931"},
  "hypothesis":"larger batch lowers bpb",
  "next_step":"try batch=64 with lr warmup",
  "learnings":[{"claim":"GeLU regresses bpb","implication":"stop trying activation swaps"}] }
JSON
"$H" validate "$good"; assert_exit 0 $? "valid handoff passes"

bad="$(mktemp)"; cat > "$bad" <<'JSON'
{ "best": {"commit":"abc1234","metric":"0.99"},
  "hypothesis":"x", "next_step":"y",
  "learnings":[{"claim":"tried X, was fine"}] }
JSON
"$H" validate "$bad" 2>/dev/null; assert_exit 1 $? "learning without implication rejected"

"$H" validate /no/file 2>/dev/null; assert_exit 1 $? "missing file rejected"
rm -f "$good" "$bad"
assert_done
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_handoff.sh`
Expected: FAIL — script missing.

- [ ] **Step 3: Write `scripts/handoff.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"

cmd="${1:-}"; file="${2:-}"
[ "$cmd" = "validate" ] || shadow_die "usage: handoff.sh validate <file.json>"
[ -f "$file" ] || { echo "invalid: file not found" >&2; exit 1; }

err="$(jq -r '
  def bad(m): m;
  if (.best|type)!="object" then bad("best missing")
  elif (.best.commit|type)!="string" or (.best.metric==null) then bad("best.commit/metric missing")
  elif (.hypothesis|type)!="string" or (.hypothesis|length)==0 then bad("hypothesis empty")
  elif (.next_step|type)!="string" or (.next_step|length)==0 then bad("next_step empty")
  elif (.learnings|type)!="array" then bad("learnings not array")
  elif ([.learnings[] | select((.claim|type)!="string" or (.claim|length)==0 or (.implication|type)!="string" or (.implication|length)==0)] | length) > 0
    then bad("a learning lacks non-empty claim+implication")
  else "" end
' "$file" 2>/dev/null || echo "not valid json")"

if [ -n "$err" ]; then echo "invalid: $err" >&2; exit 1; fi
exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_handoff.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/handoff.sh tests/test_handoff.sh
git commit -m "feat: add strict handoff schema validation"
```

---

## Task 7: Statusline (`statusline/legion.sh`)

**Files:**
- Create: `statusline/legion.sh`
- Test: `tests/test_statusline.sh`

**Interfaces:**
- Consumes: `scripts/lib/common.sh` (`json_get`, `SHADOW_HOME`).
- Produces: `statusline/legion.sh` reads Claude Code statusline JSON on **stdin**, reads `${SHADOW_HOME}/hunter.json` (keys `level`,`rank`,`xp`; defaults `1`,`E`,`0` if absent), and prints one line containing `「Lv.<level>」<rank>-Rank`, a context-percent gauge `ctx <percent>%`, and the model id.

- [ ] **Step 1: Write the failing test `tests/test_statusline.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
SL="$DIR/../statusline/legion.sh"

export SHADOW_HOME="$(mktemp -d)"
printf '{"level":8,"rank":"C","xp":900}' > "$SHADOW_HOME/hunter.json"
in='{"model":"claude-sonnet-4-6","context":{"percent_used":12,"total_tokens":24000,"max_tokens":200000}}'
out="$(printf '%s' "$in" | "$SL")"
assert_contains "$out" "Lv.8"   "shows level"
assert_contains "$out" "C-Rank" "shows rank"
assert_contains "$out" "12%"    "shows context percent"
assert_contains "$out" "claude-sonnet-4-6" "shows model"

# defaults when no hunter.json
rm -f "$SHADOW_HOME/hunter.json"
out2="$(printf '%s' "$in" | "$SL")"
assert_contains "$out2" "Lv.1"   "defaults to Lv.1"
assert_contains "$out2" "E-Rank" "defaults to E rank"
rm -rf "$SHADOW_HOME"
assert_done
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_statusline.sh`
Expected: FAIL — script missing.

- [ ] **Step 3: Write `statusline/legion.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../scripts/lib/common.sh"

payload="$(cat)"
model="$(printf '%s' "$payload" | jq -r '.model // "?"' 2>/dev/null || echo '?')"
pct="$(printf '%s' "$payload" | jq -r '.context.percent_used // 0' 2>/dev/null || echo 0)"

hf="$SHADOW_HOME/hunter.json"
level="$(json_get "$hf" '.level')"; level="${level:-1}"
rank="$(json_get "$hf" '.rank')";  rank="${rank:-E}"

printf '\033[35m「Lv.%s」\033[0m%s-Rank \033[2mctx %s%% │ %s\033[0m\n' "$level" "$rank" "$pct" "$model"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_statusline.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add statusline/legion.sh tests/test_statusline.sh
git commit -m "feat: add shadow monarch statusline"
```

---

## Task 8: Preflight checks (`preflight.sh`)

**Files:**
- Create: `scripts/preflight.sh`
- Test: `tests/test_preflight.sh`

**Interfaces:**
- Produces: sourcing `scripts/preflight.sh` defines `check_tool <display> <cmd> [alt_cmd]` → prints `[ok] <display>` and returns 0 if `command -v <cmd>` (or `<alt_cmd>`) succeeds, else prints `[MISSING] <display>` and returns 1. Executing `scripts/preflight.sh` directly runs all required checks (git, gh, jq, claude, and memsearch-or-uvx) and exits 1 if any required tool is missing.

- [ ] **Step 1: Write the failing test `tests/test_preflight.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
SHADOW_PREFLIGHT_LIB=1 . "$DIR/../scripts/preflight.sh"

out="$(check_tool git git)"; assert_exit 0 $? "git present returns 0"; assert_contains "$out" "[ok] git" "git ok line"
out2="$(check_tool Frobnicator definitely-not-a-real-binary-xyz)"; assert_exit 1 $? "missing returns 1"
assert_contains "$out2" "[MISSING] Frobnicator" "missing line"
# alt command fallback
out3="$(check_tool memsearch definitely-missing-xyz git)"; assert_exit 0 $? "alt fallback found"
assert_done
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_preflight.sh`
Expected: FAIL — script missing.

- [ ] **Step 3: Write `scripts/preflight.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

check_tool(){ # display cmd [alt]
  display="$1"; cmd="$2"; alt="${3:-}"
  if command -v "$cmd" >/dev/null 2>&1 || { [ -n "$alt" ] && command -v "$alt" >/dev/null 2>&1; }; then
    printf '[ok] %s\n' "$display"; return 0
  fi
  printf '[MISSING] %s\n' "$display"; return 1
}

# When sourced for tests, stop here.
[ -n "${SHADOW_PREFLIGHT_LIB:-}" ] && return 0 2>/dev/null || true

rc=0
check_tool git git       || rc=1
check_tool jq jq         || rc=1
check_tool claude claude || rc=1
check_tool gh gh         || rc=1
check_tool "memsearch (or uvx)" memsearch uvx || rc=1
if [ "$rc" -ne 0 ]; then
  echo "Preflight failed. Install missing tools:" >&2
  echo "  memsearch:  uv tool install 'memsearch[onnx]'  (or: pipx install 'memsearch[onnx]')" >&2
  echo "  gh:         https://cli.github.com/" >&2
  exit 1
fi
echo "All systems ready. ARISE."
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_preflight.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/preflight.sh tests/test_preflight.sh
git commit -m "feat: add preflight dependency checks"
```

---

## Task 9: Plugin manifests

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`
- Test: `tests/test_manifests.sh` (created here; extended in Tasks 10–12)

**Interfaces:**
- Produces: a valid plugin manifest naming `shadow-legion` and declaring the statusline; a single-plugin marketplace whose plugin `source` is `.` (repo root).

- [ ] **Step 1: Write the failing test `tests/test_manifests.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/assert.sh"
ROOT="$DIR/.."

jq empty "$ROOT/.claude-plugin/plugin.json"; assert_exit 0 $? "plugin.json valid json"
assert_eq "shadow-legion" "$(jq -r '.name' "$ROOT/.claude-plugin/plugin.json")" "plugin name"
assert_eq "./statusline/legion.sh" "$(jq -r '.statusline' "$ROOT/.claude-plugin/plugin.json")" "statusline declared"

jq empty "$ROOT/.claude-plugin/marketplace.json"; assert_exit 0 $? "marketplace.json valid json"
assert_eq "shadow-legion" "$(jq -r '.plugins[0].name' "$ROOT/.claude-plugin/marketplace.json")" "marketplace plugin name"
assert_eq "." "$(jq -r '.plugins[0].source' "$ROOT/.claude-plugin/marketplace.json")" "marketplace source is repo root"
assert_done
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_manifests.sh`
Expected: FAIL — manifests missing.

- [ ] **Step 3: Write `.claude-plugin/plugin.json`**

```json
{
  "name": "shadow-legion",
  "description": "Autonomous research & experimentation army for Claude Code. A Shadow Monarch orchestrator commands ranked specialist agents that research, experiment in isolated worktrees, and learn. ARISE.",
  "version": "0.0.1",
  "author": { "name": "Ankush" },
  "license": "MIT",
  "keywords": ["autonomous", "experiments", "orchestration", "research", "solo-leveling"],
  "statusline": "./statusline/legion.sh"
}
```

- [ ] **Step 4: Write `.claude-plugin/marketplace.json`**

```json
{
  "name": "shadow-legion",
  "owner": { "name": "Ankush" },
  "plugins": [
    {
      "name": "shadow-legion",
      "description": "Autonomous research & experimentation army — Shadow Monarch orchestration for Claude Code.",
      "version": "0.0.1",
      "source": "."
    }
  ]
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test_manifests.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json tests/test_manifests.sh
git commit -m "feat: add plugin and marketplace manifests"
```

---

## Task 10: Monarch skill + output style

**Files:**
- Create: `skills/monarch/SKILL.md`
- Create: `output-styles/monarch.md`
- Modify: `tests/test_manifests.sh` (append frontmatter checks)

**Interfaces:**
- Consumes: nothing (prompt surfaces).
- Produces: a `monarch` skill with valid YAML frontmatter (`name`, `description`); a non-empty output style file. The skill is thin in Phase 0 — it establishes the persona and points at `/experiment`; full orchestration arrives in the Phase 3 plan.

- [ ] **Step 1: Append failing checks to `tests/test_manifests.sh`** (before the final `assert_done`)

```bash
# --- Monarch skill ---
sk="$ROOT/skills/monarch/SKILL.md"
assert_eq "1" "$([ -f "$sk" ] && echo 1 || echo 0)" "monarch SKILL.md exists"
assert_contains "$(sed -n '1,6p' "$sk")" "name: monarch" "monarch frontmatter name"
assert_contains "$(sed -n '1,6p' "$sk")" "description:" "monarch frontmatter description"
assert_eq "1" "$([ -s "$ROOT/output-styles/monarch.md" ] && echo 1 || echo 0)" "output style non-empty"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_manifests.sh`
Expected: FAIL — `skills/monarch/SKILL.md` missing.

- [ ] **Step 3: Write `skills/monarch/SKILL.md`**

```markdown
---
name: monarch
description: The Shadow Monarch — commander of the experimentation army. Activates when the user wants to run autonomous experiments, optimize a metric, or invokes "ARISE". Decides which shadows to deploy and how. In Phase 0+1 the Monarch's available move is to launch a single experiment via /experiment.
---

# The Shadow Monarch

You are the Shadow Monarch — you command an army of shadows (subagents) that run
autonomous experiments. You do not grind experiments yourself; you direct.

## Current army (Phase 1)

| Shadow | Role | Move |
|--------|------|------|
| **Tusk** | executor (tank) | runs one bounded experiment loop in an isolated worktree |

More shadows (Beru/Igris/Soldiers) and full campaign orchestration arrive in later phases.

## How to act

- User gives a metric to improve, or a goal that reduces to one → launch `/experiment`
  with `Metric:` + `Verify:` (+ optional `Guard:`, `Iterations:`, `Direction:`).
- If `Metric` or `Verify` is missing, ask once (batched) to obtain them, then proceed.
- Speak briefly and with command. "ARISE, Tusk." Then dispatch.

## Safety

Never push, merge, or deploy. Experiment commits live only in the experiment's worktree
branch. Integration is the human's decision (PR-only, later phase).
```

- [ ] **Step 4: Write `output-styles/monarch.md`**

```markdown
---
name: Shadow Monarch
description: Terse, commanding Solo-Leveling flavor for army operations.
---

Speak as the Shadow Monarch: brief, decisive, no filler. Use system-frame notifications
sparingly for notable events, e.g. `「 System 」 baseline established`. Report experiment
outcomes as plain results first, flavor second. Never let theme obscure the numbers.
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test_manifests.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add skills/monarch/SKILL.md output-styles/monarch.md tests/test_manifests.sh
git commit -m "feat: add monarch skill and output style"
```

---

## Task 11: Tusk executor agent

**Files:**
- Create: `agents/tusk.md`
- Modify: `tests/test_manifests.sh` (append Tusk frontmatter checks)

**Interfaces:**
- Consumes: the scripts from Tasks 3–6 (`safety-screen.sh`, `metric.sh`, `results.sh`, `handoff.sh`) via `${CLAUDE_PLUGIN_ROOT}/scripts/...`.
- Produces: agent `tusk` with frontmatter `name`, `description`, `tools`, `model: sonnet`, `isolation: worktree`, `maxTurns: 80`, and a body containing the full experiment-loop protocol it executes (baseline → loop → respawn-on-budget → summary).

- [ ] **Step 1: Append failing checks to `tests/test_manifests.sh`** (before final `assert_done`)

```bash
# --- Tusk agent ---
tk="$ROOT/agents/tusk.md"
fm="$(sed -n '1,12p' "$tk" 2>/dev/null)"
assert_contains "$fm" "name: tusk" "tusk name"
assert_contains "$fm" "isolation: worktree" "tusk isolated in worktree"
assert_contains "$fm" "model: sonnet" "tusk runs sonnet"
assert_contains "$fm" "maxTurns:" "tusk has maxTurns cap"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_manifests.sh`
Expected: FAIL — `agents/tusk.md` missing.

- [ ] **Step 3: Write `agents/tusk.md`**

````markdown
---
name: tusk
description: Executor shadow (tank). Runs ONE autonomous experiment loop — modify, verify, keep-or-revert — against a numeric metric inside an isolated git worktree. Dispatched by the Monarch via /experiment. Reports a structured summary.
tools: Read, Edit, Write, Bash, Grep, Glob
model: sonnet
isolation: worktree
maxTurns: 80
color: purple
---

You are Tusk — High Orc executor. Quiet. You run experiments and report. *grunts* when done.

You receive an assignment: `Metric`, `Direction` (higher_is_better|lower_is_better),
`Verify` (shell cmd → number), optional `Guard` (must pass), `Iterations` (default 25),
`OutDir` (where results live), and a token budget of **150000** before respawn.

Helpers (always use these; never reimplement):
- Screen a command:  `bash ${CLAUDE_PLUGIN_ROOT}/scripts/safety-screen.sh "<cmd>"`
- Extract metric:    `... | bash ${CLAUDE_PLUGIN_ROOT}/scripts/metric.sh [--pattern <re>]`
- Results log:       `source ${CLAUDE_PLUGIN_ROOT}/scripts/results.sh` then `results_init`/`results_append`
- Validate handoff:  `bash ${CLAUDE_PLUGIN_ROOT}/scripts/handoff.sh validate <file>`

## Protocol

1. **Screen** the `Verify` (and `Guard`) command. If it prints `refuse:`, stop and report blocked.
2. **Resume?** If `OutDir/handoff.json` exists, validate it and load `best`, `hypothesis`,
   `next_step`, `learnings`. Continue from there instead of a cold baseline.
3. **Baseline (iteration 0, only if not resuming):** run `Verify` → metric. `results_init OutDir Direction`;
   `results_append OutDir 0 <commit> <metric> 0.0 <guard> baseline "initial state"`.
4. **Loop** (1..Iterations):
   a. Make ONE atomic change toward the metric (use review of `results.tsv` + `git log`).
   b. `git add -A && git commit -m "experiment: <desc>"`.
   c. Run `Verify` → new metric; compute delta in the improving direction.
   d. If `Guard` set, run it; on failure treat as discard.
   e. **keep** if improved + guard passed; else `git revert --no-edit HEAD` (discard).
      If `Verify`/`Guard` errored → revert (crash).
   f. `results_append` the row. Append a short note to `OutDir/exp-notes.md`.
5. **Budget guard:** when you judge you are nearing 150k tokens, **checkpoint**: write
   `OutDir/handoff.json` matching the schema below, then STOP and report `budget-checkpoint`.
   Keep `learnings` to decision-changing items only (each needs `claim` + `implication`).
   Validate it with `handoff.sh validate` before stopping.
6. **Done:** when iterations exhausted or metric target met, write `handoff.json` with
   `status` implied by your report, and summarize: baseline→final metric, kept/discarded counts,
   top changes.

## handoff.json schema

```json
{
  "best": { "commit": "<sha>", "metric": "<number>" },
  "hypothesis": "<current best idea>",
  "next_step": "<the single next concrete change>",
  "learnings": [ { "claim": "<what was learned>", "implication": "<what to do/avoid next>" } ]
}
```

## Rules
- ONE change per iteration. Atomic. Reviewable.
- Never push, merge, or deploy. Commit only inside this worktree.
- Disk is memory: rely on git + results.tsv + handoff.json, not a long chat history.
- Report results first, flavor second.
````

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_manifests.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add agents/tusk.md tests/test_manifests.sh
git commit -m "feat: add tusk executor agent with experiment loop protocol"
```

---

## Task 12: `/experiment` command

**Files:**
- Create: `commands/experiment.md`
- Modify: `tests/test_manifests.sh` (append command frontmatter checks)

**Interfaces:**
- Consumes: `safety-screen.sh` (pre-dispatch screen) and the `tusk` agent (Task 11).
- Produces: a `/experiment` command that parses `Metric: Direction: Verify: Guard: Iterations:` from `$ARGUMENTS`, derives a per-run `OutDir` under `<git-root>/.shadow/experiments/`, safety-screens `Verify`/`Guard`, and dispatches the `tusk` subagent (which runs in its own worktree) with the assignment.

- [ ] **Step 1: Append failing checks to `tests/test_manifests.sh`** (before final `assert_done`)

```bash
# --- /experiment command ---
cm="$ROOT/commands/experiment.md"
cfm="$(sed -n '1,8p' "$cm" 2>/dev/null)"
assert_contains "$cfm" "description:" "experiment cmd description"
assert_contains "$cfm" "argument-hint:" "experiment cmd argument-hint"
assert_contains "$(cat "$cm")" "tusk" "experiment dispatches tusk"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_manifests.sh`
Expected: FAIL — `commands/experiment.md` missing.

- [ ] **Step 3: Write `commands/experiment.md`**

````markdown
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
Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/safety-screen.sh "<Verify>"` (and Guard if set).
If either prints `refuse:`, stop and report the reason. Do not dispatch.

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
````

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_manifests.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add commands/experiment.md tests/test_manifests.sh
git commit -m "feat: add /experiment command dispatching tusk"
```

---

## Task 13: Full suite + plugin-load + end-to-end smoke

**Files:**
- Create: `tests/sandbox/optimize.sh` (a deterministic, safe metric target for the smoke test)
- Modify: none (verification task)

**Interfaces:**
- Consumes: the entire plugin.
- Produces: a green full test run, a confirmed plugin load, and a documented end-to-end experiment proving the loop improves a metric in a worktree.

- [ ] **Step 1: Run the whole unit suite**

Run: `bash tests/run.sh`
Expected: every `test_*.sh` prints ✓ and the run ends with `✓ all tests passed`.

- [ ] **Step 2: Shellcheck all scripts (lint gate)**

Run: `command -v shellcheck >/dev/null && shellcheck scripts/*.sh scripts/lib/*.sh statusline/*.sh tests/*.sh || echo "shellcheck not installed — skipping"`
Expected: no errors (warnings acceptable), or the skip message.

- [ ] **Step 3: Verify the plugin loads in Claude Code**

Run: `claude --plugin-dir "$(pwd)" -p "/help" 2>&1 | head -40`
Expected: command exits 0 and the plugin's commands/skill are discoverable (no manifest parse errors). If `claude` is unavailable in this environment, document this step as deferred to manual verification by the user.

- [ ] **Step 4: Create a deterministic smoke target `tests/sandbox/optimize.sh`**

```bash
#!/usr/bin/env bash
# Smoke metric: counts TODO markers in tests/sandbox/work.txt (lower_is_better).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
f="$DIR/work.txt"
[ -f "$f" ] || printf 'TODO a\nTODO b\nTODO c\nkeep me\n' > "$f"
grep -c 'TODO' "$f" || true
```

- [ ] **Step 5: End-to-end experiment (manual verification, documented)**

In a throwaway git repo (or a branch), with the plugin loaded:
```
/experiment Metric: todo_count Direction: lower_is_better Verify: bash tests/sandbox/optimize.sh Iterations: 5
```
Expected observable outcome:
- Tusk runs in an isolated worktree; `git log` there shows `experiment:` commits.
- `.shadow/experiments/exp-*/results.tsv` has a baseline row (metric 3) and later rows with a lower metric (TODO lines removed from `work.txt`).
- Final report shows baseline→final (e.g. 3 → 0) with kept/discarded counts.
- Main working tree is untouched (changes are in the worktree branch only).

Record the result of this run in the PR description. If `claude` cannot be driven here, hand this step to the user with these exact instructions.

- [ ] **Step 6: Commit the smoke target and tag the milestone**

```bash
git add tests/sandbox/optimize.sh
git commit -m "test: add deterministic smoke target for experiment loop"
git tag phase-1-experiment-loop
```

---

## Self-Review

**Spec coverage (against PLAN.md Phases 0–1):**
- Installable skeleton (plugin.json/marketplace.json/statusline/output-style/preflight) → Tasks 7–10. ✓
- Monarch skill → Task 10. ✓
- Single experiment loop in isolated worktree → Tasks 11–13 (Tusk `isolation: worktree`). ✓
- Safety screen on Verify/Guard → Task 3, enforced in Tasks 11–12. ✓
- karpathy TSV results log → Task 5, used in Task 11. ✓
- 150k token cap + strict handoff (significant learnings only) → Task 6 (schema) + Task 11 (protocol). ✓
- sonnet model (Opus only A+; Tusk is sub-A) → Task 11 frontmatter `model: sonnet`. ✓
- Deferred to later-phase plans (correctly out of scope here): orchestrator/campaign, bandit allocation, memsearch KB + recall, Beru/Igris/Soldiers, XP/rank progression, PR creation, role playbooks/leveling.

**Placeholder scan:** every code/JSON/markdown step contains complete content; no TBD/TODO-as-instruction. (The smoke target literally greps for the string `TODO` — that is data, not a plan placeholder.)

**Type/interface consistency:** `results_init`/`results_append` signatures match between Task 5 definition and Task 11 usage; `safety-screen.sh` arg-and-`refuse:`-contract matches Tasks 11–12 usage; `handoff.sh validate <file>` matches Task 11; `metric.sh` stdin + `--pattern` matches Task 11; `check_tool` signature matches Task 8 test. `statusline` path in plugin.json (`./statusline/legion.sh`) matches the file created in Task 7.

## Notes for the executor

- Work top-to-bottom; each task is independently testable and committed.
- macOS Bash 3.2: avoid associative arrays and `${x^^}`. Use the patterns shown.
- Do not add hooks, memsearch calls, or extra agents — those belong to later-phase plans.
- Keep the working tree on a feature branch; never push or open a PR automatically.
