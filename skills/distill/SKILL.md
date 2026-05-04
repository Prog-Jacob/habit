---
name: distill
description: "Use when the user wants to extract reusable patterns from their session, restructure the habit inventory, or scan all project sessions for patterns. Triggers on: distill, sweep session, extract patterns, clean up habits, inventory maintenance."
argument-hint: "[pending | project]"
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

## Sweep

1. Apply the Processing Rules: classify each prompt, interpret, dedup, and structure.
2. Check execution log for override patterns (3+ similar on same habit). Note any patterns found for Restructure to act on.
3. For each habit written, verify: run `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-habit <id>` and confirm frontmatter is valid, description starts with a verb and is under 120 chars, instruction is self-contained. If not, rewrite.
4. Verify: every new habit has a unique id, all tags are lowercase singular nouns, no two habits in the index would produce the same agent behavior. If any check fails, fix before proceeding.

## Restructure

- Merge convergent habits (would produce the same agent behavior). Compare each pair independently. If A and B merge, re-compare the result against remaining habits.
- Normalize tags (`ts`→`typescript`, `js`→`javascript`).
- Rename IDs that violate the `[a-z0-9-]` format. Flag renames in summary.
- Archive stale (never executed AND created 30+ days ago AND not updated in 30+ days).
- Act on override patterns found during Sweep: create scoped variants or update base habits.
- Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh self-heal global` and `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh self-heal project` to rebuild indexes.
- Reset meta: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh reset-meta global` and `reset-meta project`.
- Prune log: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh prune-log global` and `prune-log project`.

## Cleanup

1. Clear pending: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh clear-pending-distill`.
2. Reset prompt counter: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh reset-prompt-count ${CLAUDE_SESSION_ID}`.

## Regular (no arguments)

If the current session transcript above is empty and the pending sessions list is empty, return "Nothing to extract yet." and stop.

1. Gather prompt sources (current session transcript is already loaded above). For each entry in the pending list, fetch its transcript: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-transcript <transcript_path>`. If the file no longer exists, skip it silently. If zero usable prompts remain after fetching, return "Nothing to extract yet." and stop.
2. Run **Sweep** on gathered data.
3. Run **Cleanup**.
4. Return summary: "Merged [source] into [target]", "Created [habit-id]", "Skipped one-off messages."
5. Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh should-pending`. If it returns "yes", continue to **Pending step 2** below (the sweep and cleanup are already done).

## Pending (`$ARGUMENTS` is "pending")

Session sweep followed by full inventory restructure.

1. Run Regular steps 1–2 above. (When auto-chained from Regular step 5, skip this.)
2. Run **Restructure**.
3. Run **Cleanup**.
4. Return combined summary.

## Project (`$ARGUMENTS` is "project")

Scan all project sessions and restructure the full inventory. The preloaded transcript above is redundant; all session data is loaded fresh below.

1. Load all project sessions: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-sessions`. If it returns "No project sessions found.", return that message and stop.
2. Run **Sweep** on loaded data.
3. Run **Restructure**.
4. Run **Cleanup**.
5. Return summary: lead with what's new. "Scanned N sessions. Created [habit-id]. Merged [source] into [target]. Skipped one-off messages."
