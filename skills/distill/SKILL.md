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

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-transcript ${TRANSCRIPT_PATH:-${CLAUDE_SESSION_ID}}`

## Current Index (merged)

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-index --scope merged`

## Execution Log

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-log`

## Global Metadata

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-meta --scope global`

## Project Metadata

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-meta --scope project`

## Processing Rules

@${CLAUDE_PLUGIN_ROOT}/skills/habit-shared/PROCESSING.md

## Regular (no arguments)

1. Classify each user prompt above: reusable or one-off.
2. Apply the Processing Rules for interpretation, dedup, structuring.
3. Check execution log for override patterns (3+ similar on same habit).
4. Check metadata: `update_counter >= 50` → chain to deep.
5. Return a **human-friendly summary**. Say "Merged X into Y", "Created new habit Z", "Skipped N messages (one-off)". Do not mention file names, counters, timestamps, or pruning stats.

## Deep (`$ARGUMENTS` is "deep")

Session sweep followed by full inventory restructure.

1. Run regular steps 1 to 3 above.
2. Then restructure the full inventory:
   - Merge convergent habits (>80% overlap).
   - Normalize tags (`ts`→`typescript`, `js`→`javascript`).
   - Normalize identifiers (flag renames in summary).
   - Archive stale (no executions + not updated 90+ days).
   - Detect override patterns → create variants or update base.
   - Run `self-heal global` and `self-heal project` to rebuild indexes.
   - Reset `update_counter` to 0, update `last_deep_timestamp` via Bash.
   - Prune execution log (max 500 entries or 90 days) via Bash.
3. Return a **combined summary**. Do not mention internal files, counters, or pruning.
