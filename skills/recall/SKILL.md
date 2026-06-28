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
