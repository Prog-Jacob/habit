---
name: watch
description: "Use when the user wants to check, pause, or resume automatic habit capture. Triggers on: watch status, stop watching, pause capture, resume capture."
argument-hint: "[off|status]"
allowed-tools: Bash(bash:*)
---

# /habit:watch: Observation Control

Watch is always active by default. This skill lets you pause, resume, or check status. Watch State and Prompt Count below are already resolved.

@${CLAUDE_PLUGIN_ROOT}/skills/habit-shared/TRIGGERS.md

## Watch State

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh watch status ${CLAUDE_SESSION_ID}`

## Prompt Count

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-prompt-count ${CLAUDE_SESSION_ID}`

## Routing

Pick the first matching branch:

1. `$ARGUMENTS` is empty, "status", or "resume" -> **Status/Resume** below.
2. `$ARGUMENTS` expresses intent to deactivate (off, stop, disable, pause, turn off) -> **Pause** below.
3. Otherwise -> **Status/Resume** below (default).

## Status/Resume

1. If Watch State is `ACTIVE` -> "Watch is active. {Prompt Count} prompts captured this session." and stop.
2. Resume: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh watch start ${CLAUDE_SESSION_ID}`
3. Confirm: "Watch resumed."

## Pause

1. If Watch State is `PAUSED` -> "Watch is already paused." and stop.
2. Pause: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh watch stop ${CLAUDE_SESSION_ID}`
3. If Prompt Count > 0, suggest: "Run `/habit:distill` to process this session's patterns."
4. Confirm: "Watch paused. Run `/habit:watch` to resume."
