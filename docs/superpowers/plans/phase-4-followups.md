# Shadow Legion — Phase 4 follow-ups (non-blocking)

From the opus final review (2026-06-28). All low-risk; merged as-is.

1. **Intra-campaign semantic recall** — `commands/campaign.md` runs `kb.sh index` at intake, so the
   memsearch (semantic) path surfaces only *prior* campaigns' data. Within-campaign cross-arm recall
   currently relies on the grep fallback over freshly-written notes (which works). A **post-cycle
   `kb.sh index`** in the campaign loop would let the semantic path see within-campaign learnings too.
   *(Medium — nice enhancement for long campaigns)*
2. **`kb.sh` `$ms` unquoted expansion** — intentional (word-splitting is required for the
   `uvx --from memsearch[onnx] memsearch` form); add a one-line comment so future readers don't
   "fix" it. *(Low)*
3. **`kb.sh search` uses `grep -E`** — a query with regex-special chars is treated as a regex
   (worst case: empty results, never a crash). Optionally add `-F` for literal search, but that loses
   intentional regex use. *(Low)*

Carried: see `phase-1-followups.md`, `phase-2-followups.md`, `phase-3-followups.md`.
