---
name: distill
description: "Use when the user wants to extract reusable patterns from their session or restructure the habit inventory. Triggers on: distill, sweep session, extract patterns, clean up habits, inventory maintenance."
argument-hint: "[deep]"
context: fork
allowed-tools: Bash(bash:*)
---

# /habit:distill: Sweep & Restructure

Runs in forked subagent. All data is pre-loaded below.

## User prompts from this session

!`cat "$(cat /tmp/habit-transcript-${CLAUDE_SESSION_ID} 2>/dev/null)" 2>/dev/null | jq -r 'select(.type=="user") | .message.content | if type == "string" then . elif type == "array" then map(select(.type=="text") | .text) | join("\n") else empty end' 2>/dev/null || echo "No session data yet."`

## Current Index (merged)

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-index --scope merged`

## Execution Log

!`cat ~/.claude/habits/_log.jsonl 2>/dev/null; cat .claude/habits/_log.jsonl 2>/dev/null`

## Metadata

!`cat ~/.claude/habits/_meta.json 2>/dev/null || echo '{"version":1,"update_counter":0,"last_deep_timestamp":null}'`

## Regular (no arguments)

1. Classify each user prompt above: reusable if it describes a generalizable workflow or constraint (even if used only once), one-off if it's a question or specific debugging.
2. The merged index is loaded above.
3. Read `${CLAUDE_SKILL_DIR}/../habit-shared/PROCESSING.md`. Apply rules for interpretation, dedup, structuring.
4. Check execution log above for override patterns (3+ similar on same habit).
5. Use `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh write-habit <scope> <id>` for any writes.
6. Check metadata above: `update_counter >= 50` → chain to deep (continue with the deep steps below).
7. Return a **human-friendly summary**. Say "Merged X into Y", "Created new habit Z", "Skipped N messages (one-off)". Do not mention file names, counters, timestamps, or pruning stats.

## Deep (`$ARGUMENTS` is "deep")

Session sweep followed by full inventory restructure.

1. Run all of the regular steps above (1 to 5).
2. Then restructure the full inventory:
   - Merge convergent habits (>80% overlap).
   - Normalize tags (`ts`→`typescript`, `js`→`javascript`).
   - Normalize identifiers (flag renames in summary).
   - Archive stale (no executions + not updated 90+ days).
   - Detect override patterns → create variants or update base.
   - Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh self-heal global` and `self-heal project` to rebuild indexes.
   - Reset `update_counter` to 0, update `last_deep_timestamp` in `_meta.json` via Bash.
   - Prune `_log.jsonl` (max 500 entries or 90 days) via Bash.
3. Return a **combined summary**. Example: "Captured 2 new patterns from session. Merged `typescript-fix` into `fix-types` (same workflow). Archived `old-unused` (stale)." Do not mention internal files, counters, or pruning.
