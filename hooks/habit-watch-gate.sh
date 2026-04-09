#!/bin/bash
# Habit Watch: Lightweight prompt collector
# Runs on every UserPromptSubmit (async). Checks if watch is active.
# If active, appends the user's prompt to a queue file for batch processing.
# If not active, exits immediately. NEVER blocks, always exits 0.

INPUT=$(cat)

# Extract session_id from hook input, matches ${CLAUDE_SESSION_ID} in skills.
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
[ -z "$SESSION_ID" ] && exit 0

# Store transcript path for skills to read (runs on every prompt, not just when watching)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""')
[ -n "$TRANSCRIPT" ] && echo "$TRANSCRIPT" > "/tmp/habit-transcript-$SESSION_ID"

SENTINEL="/tmp/habit-watch-active-$SESSION_ID"

# Fast path: not watching, exit silently
[ ! -f "$SENTINEL" ] && exit 0

# Watch is active, extract prompt
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""')
[ -z "$PROMPT" ] && exit 0

# Heuristic filter: skip obvious non-reusable prompts
WORDS=$(echo "$PROMPT" | wc -w | tr -d ' ')
[ "$WORDS" -lt 7 ] && exit 0

# Passed filter, queue for processing
printf '%s\n---HABIT_SEPARATOR---\n' "$PROMPT" >> "/tmp/habit-watch-queue-$SESSION_ID"

exit 0
