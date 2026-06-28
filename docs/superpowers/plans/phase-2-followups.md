# Shadow Legion — Phase 2 follow-ups (non-blocking)

From the opus final whole-branch review (2026-06-28). The one blocker (Important #1) was fixed
on-branch (`ac9154a`); the items below are non-blocking.

1. **`dead` field is inert** — `scripts/allocate.sh` initializes every arm `dead:false` and filters
   `select(.dead==false)` in next-arm/status, but **no subcommand ever sets `dead:true`**. So the
   filtering is currently a no-op and `commands/campaign.md`'s "report dead directions" clause can
   never populate. Fix: in `update`, mark an arm `dead:true` after K consecutive non-improving
   attempts (natural use of the currently-unused `<status>` arg, or a no-improvement counter). Then
   PLATEAU/next-arm/the report all become meaningfully richer. *(Medium — makes pruning real)*
2. **`update`'s `<status>` argument is accepted but unused** (`scripts/allocate.sh`). It's the natural
   hook for #1 (mark dead on repeated `discard`/`crash`). Add a one-line comment until then. *(Low)*
3. **Live `/campaign` is human-gated** — the auto-mode classifier (correctly) refuses to let the
   assistant disable approval gates for an autonomous, subagent-spawning campaign. To run it
   hands-free, the **human** enables auto mode (`shift+tab`) or approves prompts in the session.
   Verified up to dispatch: monitor live, Monarch parse, safety screen, `allocate.sh` init.

## Carried from Phase 1 (still open)
See `phase-1-followups.md` — notably `local` in `results.sh` and wider `safety-screen` coverage,
both of which matter now that the orchestrator sources libs and screens more commands.
