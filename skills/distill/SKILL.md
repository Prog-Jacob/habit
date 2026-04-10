---
name: distill
description: "Use when the user wants to extract reusable patterns from their session or restructure the habit inventory. Triggers on: distill, sweep session, extract patterns, clean up habits, inventory maintenance."
argument-hint: "[deep]"
context: fork
allowed-tools: Bash(bash:*)
---

# /habit:distill: Sweep & Restructure

Runs in forked subagent. All data is pre-loaded below. Summaries must be human-friendly. Do not mention file names, counters, timestamps, or pruning stats.

## Triggers

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh check-triggers ${CLAUDE_SESSION_ID}`

## User prompts from this session

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-transcript ${CLAUDE_SESSION_ID}`

## Current Index (merged)

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-index --scope merged`

## Watch Queue (if active)

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-watch-queue ${CLAUDE_SESSION_ID}`

## Execution Log

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-log`

## Global Metadata

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-meta --scope global`

## Project Metadata

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-meta --scope project`

## Processing Rules

@${CLAUDE_PLUGIN_ROOT}/skills/habit-shared/PROCESSING.md

## Regular (no arguments)

If triggers above show `deep`, chain to the deep flow below after completing these steps.

1. Classify each prompt above (transcript and watch queue): reusable or one-off.
2. Apply the Processing Rules for interpretation, dedup, structuring.
3. Check execution log for override patterns (3+ similar on same habit).
4. Clear the watch queue: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh clear-watch-queue ${CLAUDE_SESSION_ID}`.
5. Return summary. Say "Merged X into Y", "Created new habit Z", "Skipped N messages (one-off)".

## Deep (`$ARGUMENTS` is "deep")

Session sweep followed by full inventory restructure.

1. Run regular steps 1 to 4 above.
2. Restructure the full inventory:
   - Merge convergent habits (>80% overlap).
   - Normalize tags (`ts`→`typescript`, `js`→`javascript`).
   - Normalize identifiers (flag renames in summary).
   - Archive stale (no executions + not updated 30+ days).
   - Detect override patterns → create variants or update base.
   - Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh self-heal global` and `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh self-heal project` to rebuild indexes.
   - Reset meta: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh reset-meta global` and `reset-meta project`.
   - Prune log: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh prune-log global` and `prune-log project`.
3. Return combined summary.
