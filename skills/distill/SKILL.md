---
name: distill
description: 'Sweep the current session to extract reusable patterns, or restructure the full habit inventory. Use when the user wants to capture habits from their conversation, says "distill", "extract patterns", "sweep session", or wants to clean up their habit collection.'
argument-hint: "[deep]"
context: fork
allowed-tools: Read Write Edit
---

# /habit:distill: Sweep & Restructure

Runs in forked subagent. User prompts from this session are pre-loaded below.

## User prompts from this session

!`cat "$(cat /tmp/habit-transcript-${CLAUDE_SESSION_ID} 2>/dev/null)" 2>/dev/null | jq -r 'select(.type=="user") | .message.content | if type == "string" then . elif type == "array" then map(select(.type=="text") | .text) | join("\n") else empty end' 2>/dev/null || echo "No session data yet."`

## Regular (no arguments)

1. Classify each user prompt above: reusable if it describes a generalizable workflow or constraint (even if used only once), one-off if it's a question or specific debugging.
2. Load merged index from both scopes.
3. Read `${CLAUDE_SKILL_DIR}/../habit-shared/PROCESSING.md`. Apply rules for interpretation, dedup, structuring.
4. Read `_log.jsonl` to detect override patterns (3+ similar on same habit).
5. Check `_meta.json`: `update_counter >= 20` → chain to deep (continue with the deep steps below).
6. Return a **human-friendly summary**. Focus on what changed for the user, not implementation details. Say "Merged X into Y", "Created new habit Z", "Skipped N messages (one-off)". Do not mention file names, counters, timestamps, or pruning stats.

## Deep (`$ARGUMENTS` is "deep")

Session sweep followed by full inventory restructure.

1. Run all of the regular steps above (1–4).
2. Then restructure the full inventory:
   - Merge convergent habits (>80% overlap).
   - Normalize tags (`ts`→`typescript`, `js`→`javascript`).
   - Normalize identifiers (flag renames in summary).
   - Archive stale (no executions + not updated 90+ days).
   - Detect override patterns → create variants or update base.
   - Rebuild `_index.json` from source `.md` (canonical, not patch).
   - Reset `update_counter` to 0, update `last_deep_timestamp`.
   - Prune `_log.jsonl` (max 500 entries or 90 days).
3. Return a **combined summary** covering both the sweep and the restructure. Example: "Captured 2 new patterns from session. Merged `typescript-fix` into `fix-types` (same workflow). Archived `old-unused` (stale)." Do not mention internal files, counters, or pruning.
