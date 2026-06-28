# Shadow Legion — Phase 3 follow-ups (non-blocking)

From the opus final review (2026-06-28). All cosmetic; merged as-is.

1. **`scripts/allocate.sh` `update`** declares `tmp="$sf.tmp"` but writes to the literal `"$sf.tmp"` — the `tmp` var is now dead. Drop it or use it (match `add-arm`/`mark-dead` style). *(Low)*
2. **`scripts/allocate.sh` usage string** doesn't list the new subcommands (`dead-candidates|mark-dead|dead-report`). Update for discoverability. *(Low)*
3. **Plan dry-run example off-by-one** (doc only): the Phase-3 plan's Task-4 dry-run says `candidates@2: a1` after one non-improving update, but with `dead_k=2` an arm needs its baseline update + **2** non-improving updates (streak 2) to be a candidate. The code + unit tests are correct; only the plan prose example is wrong. *(Doc)*

Carried from earlier: see `phase-1-followups.md` (`local` in results.sh, wider safety-screen coverage) and `phase-2-followups.md`.
