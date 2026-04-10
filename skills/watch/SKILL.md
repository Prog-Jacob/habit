---
name: watch
description: "Use when the user wants to start or stop automatic habit capture. Triggers on: watch my session, observe patterns, start capturing, automatic habit detection from conversation."
argument-hint: "[off]"
allowed-tools: Bash(bash:*)
---

# /habit:watch: Observation Toggle

## Watch State

!`test -f /tmp/habit-watch-active-${CLAUDE_SESSION_ID} && echo "ACTIVE" || echo "INACTIVE"`

## User prompts from this session

!`cat "$(cat /tmp/habit-transcript-${CLAUDE_SESSION_ID} 2>/dev/null)" 2>/dev/null | jq -r 'select(.type=="user") | .message.content | if type == "string" then . elif type == "array" then map(select(.type=="text") | .text) | join("\n") else empty end' 2>/dev/null || echo "No session data yet."`

## Deactivate (`$ARGUMENTS` is `off`, `stop`, or `disable`)

1. If Watch State above is `INACTIVE` → "Watch wasn't active." and stop.
2. Remove `/tmp/habit-watch-active-${CLAUDE_SESSION_ID}` via Bash.
3. Drain watch queue per Section 6 of `${CLAUDE_SKILL_DIR}/../habit-shared/PROCESSING.md`. Use `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh write-habit <scope> <id>` for any writes.
4. Print summary: created N, updated M. List ids.
5. Clean up temp files.

## Activate (no arguments)

1. If Watch State above is `ACTIVE` → "Already watching." and stop.
2. Create sentinel via Bash: `touch /tmp/habit-watch-active-${CLAUDE_SESSION_ID}`
3. Initialize queue via Bash: `touch /tmp/habit-watch-queue-${CLAUDE_SESSION_ID}`
4. Sweep session using the user prompts listed above. Classify each: reusable if it describes a generalizable workflow or constraint (even if used only once), one-off if it's a question or specific debugging. Apply PROCESSING.md rules for reusable candidates. Use `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh write-habit <scope> <id>` for any writes.
5. Confirm: "Watching. Swept session so far: captured N patterns." List captured habit ids and one-line descriptions.

Hook collects subsequent prompts to queue asynchronously. Queue is processed on deactivation.
