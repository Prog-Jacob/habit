---
name: habit-watch
description: 'Start or stop watching the session for reusable patterns. Use when the user wants to capture habits automatically, says "watch my session", "observe patterns", "start capturing", or wants automatic habit detection from their conversation.'
argument-hint: "[off]"
---

# /habit-watch: Observation Toggle

## Deactivate (`$ARGUMENTS` is `off`, `stop`, or `disable`)

1. Remove `/tmp/habit-watch-active-$PPID`. Missing → "Watch wasn't active." and stop.
2. Read queue `/tmp/habit-watch-queue-$PPID` (prompts separated by `---HABIT_SEPARATOR---`).
3. Classify each: reusable or one-off. A prompt is reusable if it describes a workflow, procedure, or constraint that would apply in future contexts, even if used only once in this session. Frequency doesn't matter; generalizability does. One-off = questions, debugging specific errors, casual chat. For reusable: read `~/.claude/skills/habit-shared/PROCESSING.md`, apply rules, check index for dedup.
4. Print summary: created N, updated M. List ids.
5. Clean up temp files.

## Activate (no arguments)

1. `/tmp/habit-watch-active-$PPID` exists → "Already watching." and stop.
2. Create sentinel. Initialize queue.
3. Sweep session: read `$TRANSCRIPT_PATH`, only extract user messages (skip assistant responses, tool calls, system messages). Classify each: reusable if it describes a generalizable workflow or constraint (even if used only once), one-off if it's a question or specific debugging. Apply PROCESSING.md rules for reusable candidates.
4. Confirm: "Watching. Swept session so far: captured N patterns." List captured habit ids and one-line descriptions, same format as deactivation summary.

Hook collects subsequent prompts to queue asynchronously. Queue is processed on deactivation (`/habit-watch off`). Running `/habit-distill` separately reads the full transcript, which covers the same messages, but does not consume the queue.
