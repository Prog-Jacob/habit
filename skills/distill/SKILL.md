---
name: distill
description: "Use when the user wants to extract reusable patterns from their session or restructure the habit inventory. Triggers on: distill, sweep session, extract patterns, clean up habits, inventory maintenance."
argument-hint: "[deep]"
context: fork
allowed-tools: Bash(bash:*)
---

# /habit:distill: Sweep & Restructure

Runs in forked subagent. All data is pre-loaded below. Use only Bash commands from the Operations reference for writes. Summaries must be human-friendly. Do not mention file names, counters, timestamps, or pruning stats.

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

!`cat ${CLAUDE_PLUGIN_ROOT}/skills/habit-shared/PROCESSING.md`

## Operations

!`cat ${CLAUDE_PLUGIN_ROOT}/skills/habit-shared/OPERATIONS.md`

## Regular (no arguments)

If the current session transcript above has fewer than 5 user prompts and the pending sessions list is empty, return "Nothing to extract yet." and stop.

1. Gather prompt sources (current session transcript is already loaded above):
   - For each entry in the pending list, fetch its transcript: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-transcript <transcript_path>`. If the file no longer exists, skip it silently.
   - If zero usable prompts remain after fetching, return "Nothing to extract yet." and stop.
2. Apply the Processing Rules: classify each prompt, interpret, dedup, and structure.
3. Check execution log for override patterns (3+ similar on same habit).
4. For each habit written, verify: run `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-habit <id>` and confirm frontmatter is valid, description starts with a verb and is under 120 chars, instruction is self-contained. If not, rewrite.
5. Clear pending: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh clear-pending-distill`.
6. Reset prompt counter: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh reset-prompt-count ${CLAUDE_SESSION_ID}`.
7. Before returning, verify: every new habit has a unique id, all tags are lowercase singular nouns, no two habits in the index would produce the same agent behavior. If any check fails, fix before proceeding.
8. Return summary: "Merged [source] into [target]", "Created [habit-id]", "Skipped one-off messages."
9. Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh should-deep`. If it returns "yes", continue to **step 2** of the Deep flow below (the regular sweep is already done).

## Deep (`$ARGUMENTS` is "deep")

Session sweep followed by full inventory restructure.

1. Run Regular steps 1–8 above. (When auto-chained from Regular step 9, skip this; the sweep is already done.)
2. Restructure the full inventory:
   - Merge convergent habits (would produce the same agent behavior). Compare each pair independently. If A and B merge, re-compare the result against remaining habits.
   - Normalize tags (`ts`→`typescript`, `js`→`javascript`).
   - Rename IDs that violate the `[a-z0-9-]` format. Flag renames in summary.
   - Archive stale (never executed AND created 30+ days ago AND not updated in 30+ days).
   - Detect override patterns → create variants or update base.
   - Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh self-heal global` and `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh self-heal project` to rebuild indexes.
   - Reset meta: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh reset-meta global` and `reset-meta project`.
   - Prune log: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh prune-log global` and `prune-log project`.
3. Return combined summary.
