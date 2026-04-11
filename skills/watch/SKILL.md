---
name: watch
description: "Use when the user wants to start or stop automatic habit capture. Triggers on: watch my session, observe patterns, start capturing, automatic habit detection from conversation."
argument-hint: "[off]"
allowed-tools: Bash(bash:*)
---

# /habit:watch: Observation Toggle

## Triggers

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh check-triggers ${CLAUDE_SESSION_ID}`

## Watch State

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-watch-state ${CLAUDE_SESSION_ID}`

## Processing Rules

@${CLAUDE_PLUGIN_ROOT}/skills/habit-shared/PROCESSING.md

## Deactivate (`$ARGUMENTS` expresses intent to deactivate, e.g. off, stop, disable, pause, turn off)

1. If Watch State above is `INACTIVE` → "Watch wasn't active." and stop.
2. Stop collecting: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh watch-stop ${CLAUDE_SESSION_ID}`
3. Read the queue: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-watch-queue ${CLAUDE_SESSION_ID}`
4. If queue has prompts (separated by `---HABIT_SEPARATOR---` markers):
   - Classify each: reusable or one-off.
   - Apply the Processing Rules (interpretation, dedup, scope detection).
   - Write each via `write-habit` (see Processing Rules for the full command).
5. Clear queue: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh clear-watch-queue ${CLAUDE_SESSION_ID}`
6. Print summary: created N, updated M. List ids.

## Activate (no arguments)

1. If Watch State above is `ACTIVE` → "Already watching." and stop.
2. Start watch: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh watch-start ${CLAUDE_SESSION_ID}`
3. Confirm: "Watching. I'll capture patterns as you work. Run `/habit:watch off` to stop and process."
