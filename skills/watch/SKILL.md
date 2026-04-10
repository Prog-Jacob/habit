---
name: watch
description: "Use when the user wants to start or stop automatic habit capture. Triggers on: watch my session, observe patterns, start capturing, automatic habit detection from conversation."
argument-hint: "[off]"
allowed-tools: Bash(bash:*)
---

# /habit:watch: Observation Toggle

## Watch State

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-watch-state ${CLAUDE_SESSION_ID}`

## User prompts from this session

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-transcript ${CLAUDE_SESSION_ID}`

## Processing Rules

@${CLAUDE_PLUGIN_ROOT}/skills/habit-shared/PROCESSING.md

## Deactivate (`$ARGUMENTS` is `off`, `stop`, or `disable`)

1. If Watch State above is `INACTIVE` → "Watch wasn't active." and stop.
2. Remove `/tmp/habit-watch-active-${CLAUDE_SESSION_ID}` via Bash.
3. Drain watch queue per Section 6 above.
4. Print summary: created N, updated M. List ids.
5. Clean up temp files.

## Activate (no arguments)

1. If Watch State above is `ACTIVE` → "Already watching." and stop.
2. Create sentinel via Bash: `touch /tmp/habit-watch-active-${CLAUDE_SESSION_ID}`
3. Initialize queue via Bash: `touch /tmp/habit-watch-queue-${CLAUDE_SESSION_ID}`
4. Sweep session using the user prompts above. Classify each: reusable if it describes a generalizable workflow or constraint (even if used only once), one-off if it's a question or specific debugging. Apply the Processing Rules for reusable candidates.
5. Confirm: "Watching. Swept session so far: captured N patterns." List captured habit ids and one-line descriptions.

Hook collects subsequent prompts to queue asynchronously. Queue is processed on deactivation.
