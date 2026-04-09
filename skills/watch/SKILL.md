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
3. Sweep session: read the transcript path from `/tmp/habit-transcript-${CLAUDE_SESSION_ID}` (one line, written by the hook), then read that file. If the file doesn't exist, tell the user "No session data yet, send a message first, then retry." Only extract user messages (skip assistant responses, tool calls, system messages). Classify each: reusable if it describes a generalizable workflow or constraint (even if used only once), one-off if it's a question or specific debugging. Apply PROCESSING.md rules for reusable candidates.
4. Confirm: "Watching. Swept session so far: captured N patterns." List captured habit ids and one-line descriptions, same format as deactivation summary.

Hook collects subsequent prompts to queue asynchronously. Queue is processed on deactivation (`/habit:watch off`). Running `/habit:distill` separately reads the full transcript, which covers the same messages, but does not consume the queue.
