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

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-index merged`

## Pending Sessions (from prior sessions)

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-pending-distill`

## Execution Log

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-log`

## Global Metadata

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-meta global`

## Project Metadata

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-meta project`

## Processing Rules

@${CLAUDE_PLUGIN_ROOT}/skills/habit-shared/PROCESSING.md

## Operations

@${CLAUDE_PLUGIN_ROOT}/skills/habit-shared/OPERATIONS.md

## Regular (no arguments)

If triggers above show `deep`, chain to the deep flow below after completing these steps.

1. Gather all prompt sources:
   - Current session transcript (loaded above).
   - For each pending session breadcrumb: read its transcript via `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-transcript <transcript_path>`.
2. Classify each prompt: reusable or one-off.
3. Apply the Processing Rules for interpretation, dedup, structuring.
4. Check execution log for override patterns (3+ similar on same habit).
5. Clear pending: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh clear-pending-distill`.
6. Reset prompt counter: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh reset-prompt-count ${CLAUDE_SESSION_ID}`.
7. Return summary. Say "Merged X into Y", "Created new habit Z", "Skipped N messages (one-off)".

## Deep (`$ARGUMENTS` is "deep")

Session sweep followed by full inventory restructure.

1. Run regular steps 1 to 6 above.
2. Restructure the full inventory:
   - Merge convergent habits (>80% overlap).
   - Normalize tags (`ts`→`typescript`, `js`→`javascript`).
   - Normalize identifiers (flag renames in summary).
   - Archive stale (`last_executed` is null or 30+ days ago, and not updated 30+ days).
   - Detect override patterns → create variants or update base.
   - Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh self-heal global` and `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh self-heal project` to rebuild indexes.
   - Reset meta: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh reset-meta global` and `reset-meta project`.
   - Prune log: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh prune-log global` and `prune-log project`.
3. Return combined summary.
