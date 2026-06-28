# Shadow Legion — Phase 6 follow-ups (non-blocking)

From the opus final review (2026-06-29). The Minor items below were either fixed on-branch or are cosmetic.

1. **Igris `BaseRef` vs `Baseline`** — FIXED (`f928b76`): Igris now takes an explicit `BaseRef` (git ref
   for the gaming-detection diff) distinct from `Baseline` (the numeric metric); campaign §5 passes it.
2. **Stale "Phase 0+1" line in monarch skill description** — FIXED (`f928b76`): description refreshed to
   the current roster (Beru/Tusk/Igris + campaigns).
3. **Igris worktree leak on Verify crash** — self-correcting: the next run's `git worktree remove -f …
   2>/dev/null` before re-add cleans any stale `/tmp/shadow-verify-*`. No action needed. *(Low)*

Carried: see `phase-1`…`phase-5`-followups.md. Highest-value carried item remains the post-cycle
`kb.sh index` (Phase 4 #1) so semantic recall sees within-campaign learnings.
