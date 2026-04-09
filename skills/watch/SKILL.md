---
name: watch
description: 'Start or stop watching the session for reusable patterns. Use when the user wants to capture habits automatically, says "watch my session", "observe patterns", "start capturing", or wants automatic habit detection from their conversation.'
argument-hint: "[off]"
allowed-tools: Read Write Bash
---

# /habit:watch: Observation Toggle

## Deactivate (`$ARGUMENTS` is `off`, `stop`, or `disable`)

1. Remove `/tmp/habit-watch-active-${CLAUDE_SESSION_ID}`. Missing → "Watch wasn't active." and stop.
2. Drain watch queue per Section 6 of `${CLAUDE_SKILL_DIR}/../habit-shared/PROCESSING.md`.
3. Print summary: created N, updated M. List ids.
4. Clean up temp files.

## Activate (no arguments)

1. `/tmp/habit-watch-active-${CLAUDE_SESSION_ID}` exists → "Already watching." and stop.
2. Create sentinel. Initialize queue.
3. Sweep session using the user prompts listed below. Classify each: reusable if it describes a generalizable workflow or constraint (even if used only once), one-off if it's a question or specific debugging. Apply PROCESSING.md rules for reusable candidates.
4. Confirm: "Watching. Swept session so far: captured N patterns." List captured habit ids and one-line descriptions, same format as deactivation summary.

## User prompts from this session

!`cat "$(cat /tmp/habit-transcript-${CLAUDE_SESSION_ID} 2>/dev/null)" 2>/dev/null | jq -r 'select(.type=="user") | .message.content | if type == "string" then . elif type == "array" then map(select(.type=="text") | .text) | join("\n") else empty end' 2>/dev/null || echo "No session data yet."`

Hook collects subsequent prompts to queue asynchronously. Queue is processed on deactivation (`/habit:watch off`). Running `/habit:distill` separately reads the full transcript, which covers the same messages, but does not consume the queue.
