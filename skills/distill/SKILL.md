---
name: distill
description: "Use when the user wants to extract reusable patterns from their session, restructure the habit inventory, or scan all project sessions for patterns. Triggers on: distill, sweep session, extract patterns, clean up habits, inventory maintenance."
argument-hint: "[maintain | project]"
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

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-shared PROCESSING.md`

## Operations

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-shared OPERATIONS.md`

## Routing

Arguments: `$ARGUMENTS`

Pick the first matching branch. Do not read or execute other branches.

1. Arguments line above contains "project" → go to **Project** below.
2. Arguments line above contains "maintain", "pending", or "deep" → go to **Maintain** below.
3. Arguments line above is empty → go to **Regular** below.

---

## Project

Scan all project sessions and restructure the full inventory. Ignore the preloaded session transcript above; all session data is loaded fresh here.

1. Load all project sessions: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-sessions`. If it returns "No project sessions found.", return that message and stop.
2. Run **Sweep** on loaded data.
3. Run **Restructure**.
4. Run **Self-improve**.
5. Run **Cleanup**.
6. Return summary: lead with what's new. "Scanned N sessions. Created [habit-id]. Merged [source] into [target]. Skipped one-off messages."

## Maintain

Session sweep followed by full inventory restructure and plugin self-improvement.

1. If the current session transcript above is empty and the pending sessions list is empty, skip to step 3.
2. Gather prompt sources (current session transcript is already loaded above). For each entry in the pending list, fetch its transcript: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-transcript <transcript_path>`. If the file no longer exists, skip it silently. Run **Sweep** on gathered data if any usable prompts exist.
3. Run **Restructure**.
4. Run **Self-improve**.
5. Run **Cleanup**.
6. Return combined summary.

## Regular

1. If the current session transcript above is empty and the pending sessions list is empty, return "Nothing to extract yet." and stop.
2. Gather prompt sources (current session transcript is already loaded above). For each entry in the pending list, fetch its transcript: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-transcript <transcript_path>`. If the file no longer exists, skip it silently. If zero usable prompts remain after fetching, return "Nothing to extract yet." and stop.
3. Run **Sweep** on gathered data.
4. Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh should-pending`. If it returns "yes", continue to **Maintain step 3** (skip step 5; Maintain ends with its own Cleanup).
5. Run **Cleanup**.
6. Return summary: "Merged [source] into [target]", "Created [habit-id]", "Skipped one-off messages."

---

## Sweep

1. Apply the Processing Rules: classify each prompt, interpret, dedup, and structure.
2. For each reusable pattern found, write or merge via the `write-habit` command (see Operations).
3. Check execution log for override patterns (3+ similar on same habit). List any patterns found. Restructure will act on this list later in the same flow.
4. For each habit written, verify: run `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-habit <id>` and confirm frontmatter is valid, description starts with a verb and is under 120 chars, instruction is self-contained. If not, rewrite.
5. Verify: every new habit has a unique id, all tags are lowercase singular nouns, no two habits in the index would produce the same agent behavior. If any check fails, fix before proceeding.

## Restructure

- Merge convergent habits (would produce the same agent behavior). Compare each pair independently. If A and B merge, re-compare the result against remaining habits.
- Normalize tags (`ts`→`typescript`, `js`→`javascript`).
- Rename IDs that violate the `[a-z0-9-]` format. Flag renames in summary.
- Archive stale (never executed AND created 30+ days ago AND not updated in 30+ days).
- Act on override patterns found during Sweep: create scoped variants or update base habits.
- Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh self-heal global` and `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh self-heal project` to rebuild indexes.
- Reset meta: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh reset-meta global` and `reset-meta project`.
- Prune log: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh prune-log global` and `prune-log project`.

## Self-improve

Read observations: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-observations`. If none, skip.

For each observation, identify the plugin source file responsible (under `${CLAUDE_PLUGIN_ROOT}/skills/` or `${CLAUDE_PLUGIN_ROOT}/bin/`). Read the file, apply the smallest edit that resolves the friction. Preserve existing structure and style. If no source file in `${CLAUDE_PLUGIN_ROOT}/skills/` or `${CLAUDE_PLUGIN_ROOT}/bin/` clearly maps to the observation, skip that observation and note it in the summary instead of editing anything.

## Cleanup

1. Clear pending: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh clear-pending-distill`.
2. Clear observations: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh clear-observations`.
3. Reset prompt counter: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh reset-prompt-count ${CLAUDE_SESSION_ID}`.
