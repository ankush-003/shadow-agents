# Shadow Legion — Phase 0+1 follow-ups (non-blocking)

From the final whole-branch review (2026-06-28). None block Phase 0+1; fold into Phase 2/3.
**Prioritized** — the first two become load-bearing once the orchestrator sources libraries in a loop.

1. **results.sh: add `local`** to `results_init`/`results_append` (`outdir`/`direction`/`ts` currently leak as globals). Matters once the orchestrator sources it in a loop. *(High)*
2. **safety-screen.sh: widen coverage** before it's relied upon — handle separated `rm -r -f` ordering and case-insensitivity; add tests for the untested categories (`mkfs`, `dd if=`, `> /etc`, `AWS_SECRET`, `PRIVATE KEY`). *(High)*
3. **tusk.md: reconcile `status`** — it appears in step-6 prose but not the handoff JSON schema block. Add it to the schema or drop it from prose. *(Low, doc)*
4. **common.sh `shadow_die`**: color gated on `[ -t 1 ]` (stdout) but writes to fd 2; decided at source time. Cosmetic. *(Low)*
5. **metric.sh**: `--pattern` with no argument silently falls back to default mode; no `shift`. Harmless degradation. *(Low)*
6. **handoff.sh**: zero-arg error says "file not found" (mildly misleading; exit code correct). *(Low)*
7. **preflight.sh**: install hints cover only `gh`/`memsearch`, not `git`/`jq`/`claude`. *(Low)*
8. **test_manifests.sh**: frontmatter checks use `sed -n '1,6p'`/`'1,12p'` — brittle if frontmatter grows. *(Low)*
9. **experiment.md**: no explicit guard for unset `CLAUDE_PLUGIN_ROOT` (guaranteed by runtime); OutDir relative-vs-absolute is self-resolved in the dispatch block. *(Low)*

## Operational (not code)
- **Plugin load: VERIFIED** — `claude --plugin-dir "$(pwd)" --model haiku -p ...` returned cleanly (exit 0, no manifest parse errors), confirming plugin.json/marketplace.json/component manifests are accepted.
- **Remaining manual check — live `/experiment` end-to-end run** (documented in `.superpowers/sdd/task-13-report.md`): sandbox target `tests/sandbox/optimize.sh`, expect baseline 3 → lower, experiment commits in an isolated worktree, main tree untouched. Not exercised in CI because it spawns the Tusk subagent in a worktree.
