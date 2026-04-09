---
name: habit-distill
description: 'Sweep the current session to extract reusable patterns, or restructure the full habit inventory. Use when the user wants to capture habits from their conversation, says "distill", "extract patterns", "sweep session", or wants to clean up their habit collection.'
argument-hint: "[deep]"
context: fork
---

# /habit-distill: Sweep & Restructure

Runs in forked subagent.

## Regular (no arguments)

1. Read `$TRANSCRIPT_PATH`, only extract user messages (skip assistant responses, tool calls, system messages). Classify each: reusable if it describes a generalizable workflow or constraint (even if used only once), one-off if it's a question or specific debugging.
2. Load merged index from both scopes.
3. Read `~/.claude/skills/habit-shared/PROCESSING.md`. Apply rules for interpretation, dedup, structuring.
4. Read `_log.jsonl` to detect override patterns (3+ similar on same habit).
5. Check `_meta.json`: `update_counter >= 50` → chain to deep.
6. Return a **human-friendly summary**. Focus on what changed for the user, not implementation details. Say "Merged X into Y", "Created new habit Z", "Skipped N messages (one-off)". Do not mention file names, counters, timestamps, or pruning stats.

## Deep (`$ARGUMENTS` is "deep")

Full inventory restructure. Does NOT read session transcript.

1. Read all `.md` files + `_log.jsonl` from both scopes.
2. Apply PROCESSING.md rules, plus:
   - Merge convergent habits (>80% overlap).
   - Normalize tags (`ts`→`typescript`, `js`→`javascript`).
   - Normalize identifiers (flag renames in summary).
   - Archive stale (no executions + not updated 90+ days).
   - Detect override patterns → create variants or update base.
   - Rebuild `_index.json` from source `.md` (canonical, not patch).
   - Reset `update_counter` to 0, update `last_deep_timestamp`.
   - Prune `_log.jsonl` (max 500 entries or 90 days).
3. Return a **human-friendly summary**: what was merged, archived, renamed, and created. Example: "Merged `typescript-fix` into `fix-types` (same workflow). Archived `old-unused` (stale). Created `fix-types-auth` from a repeated override pattern." Do not mention internal files, counters, or pruning.
