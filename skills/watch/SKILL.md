---
name: habit-watch
description: "Use when the user wants to check, pause, or resume automatic habit capture. Triggers on: watch status, stop watching, pause capture, resume capture."
argument-hint: "[start|stop|status]"
allowed-tools: Bash(bash:*)
disable-model-invocation: true
---

# Habit Watch: Observation Control

Watch is always active by default. This skill lets you check status, pause, or resume. Capture control is deliberately static: watch has no learnings overlay, by design.

## Preload

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh skill-preload watch ${CLAUDE_SESSION_ID}`

Run this Setup block once and reuse the values below:

```bash
HABIT_SID_FILE=$(ls -t "$HOME/.claude/habits/sessions.d/"* 2>/dev/null | head -1)
source "${HABIT_SID_FILE:-$HOME/.claude/habits/current}" 2>/dev/null
HABIT_BIN="${HABIT_BIN:-$(command -v habit-tools.sh || echo "${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin/habit-tools.sh}")}"
[ -f "${HABIT_BIN:-}" ] || echo "HABIT_UNAVAILABLE: habit is not wired on this host."
```

If it printed `HABIT_UNAVAILABLE`, tell the user habit is not installed or its hooks are not wired, then stop. Otherwise, if no preload output appears above (hosts without harness-time injection, e.g. Cursor), run `bash "$HABIT_BIN" skill-preload watch "$HABIT_SID"` once.

The output has a `===TRIGGERS===` section: show the message only if non-empty.

## Resolve state

Run these and use the outputs (`ACTIVE` or `PAUSED`, then the count):

```bash
bash "$HABIT_BIN" watch status "$HABIT_SID"
bash "$HABIT_BIN" read-prompt-count "$HABIT_SID"
```

## Routing

1. Message empty, "status", or "resume" go to Status/Resume.
2. Message intends deactivation (off, stop, disable, pause, turn off) go to Pause.
3. Otherwise go to Status/Resume.

## Status/Resume

1. If `ACTIVE`: count 0 says "Watch is active. No prompts captured yet this session.", else "Watch is active. {count} prompts captured this session." Include the triggers message if non-empty. Stop.
2. Resume: `bash "$HABIT_BIN" watch start "$HABIT_SID"`
3. Confirm: "Watch resumed."

## Pause

1. If `PAUSED`: "Watch is already paused." Stop.
2. Pause: `bash "$HABIT_BIN" watch stop "$HABIT_SID"`
3. If count > 0, suggest running the distill habit to process this session.
4. Confirm: "Watch paused. Run the watch habit to resume."
