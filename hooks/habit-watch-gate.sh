#!/bin/bash
# Habit Watch: Lightweight prompt collector
# Runs on every UserPromptSubmit (async). Checks if watch is active.
# If active, appends the user's prompt to a queue file for batch processing.
# If not active, exits immediately. NEVER blocks, always exits 0.

INPUT=$(cat)

# Always use PPID for sentinel, matches what the skills use.
SENTINEL="/tmp/habit-watch-active-$PPID"

# Fast path: not watching, exit silently
[ ! -f "$SENTINEL" ] && exit 0

# Watch is active, extract prompt and append to queue
PROMPT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))" 2>/dev/null)
if [ -n "$PROMPT" ]; then
  printf '%s\n---HABIT_SEPARATOR---\n' "$PROMPT" >> "/tmp/habit-watch-queue-$PPID"
fi

exit 0
