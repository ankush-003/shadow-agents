# Shadow Legion — Phase 5 follow-ups (non-blocking)

From the opus final review (2026-06-29). The one Important item (tusk delta inconsistency) was fixed
on-branch (`7941954`); the items below are cosmetic.

1. **preflight `[opt] gh` line prints to stdout before the rc check** — on a failing run the optional
   gh line appears above the "Preflight failed" stderr block. Harmless (informational, no exit impact);
   could reorder in a polish pass. *(Low)*
2. **`mean_delta` rounding** — done for the winning-approach line (`7941954`); the per-arm table in
   PROPOSAL.md still prints raw `mean_delta`. Optional: round there too for fully clean tables. *(Low)*

Carried: see `phase-1`/`phase-2`/`phase-3`/`phase-4`-followups.md.
Highest-value carried item: post-cycle `kb.sh index` (Phase 4 #1) so semantic recall sees
within-campaign learnings.
