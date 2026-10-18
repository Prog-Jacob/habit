---
name: habit-watch
description: "Use when the user wants to check, pause, or resume prompt capture, or see and remove what habit has learned about its own skills. Triggers on: watch status, stop watching, pause capture, resume capture, list learnings, forget a learning."
argument-hint: "[off [hours] | on | learnings | forget <n>]"
allowed-tools: Bash(bash:*)
disable-model-invocation: true
---

# Habit Watch: Capture Control

Capture is on by default: each prompt goes to a local inbox that the distill habit reads. Watch has no learnings overlay, by design.

## Preload

Run this once before anything else:

```bash
bash ~/.claude/habits/bin/habit-tools.sh preload watch
```

If the command is missing, tell the user habit's hooks have not run yet and to start a new session, then stop.

The output is the capture state (`ACTIVE`, or `PAUSED until` a local time), the prompts waiting for distill, and the last capture time.

## Routing

1. Pause intent (off, stop, pause, disable), with optional hours: run `bash ~/.claude/habits/bin/habit-tools.sh watch off [hours]` (8 hours when none are given). Confirm when capture resumes on its own.
2. Resume intent (on, start, resume): run `bash ~/.claude/habits/bin/habit-tools.sh watch on`. Confirm "Capture resumed."
3. Learnings intent (learnings, what have you learned): run `bash ~/.claude/habits/bin/habit-tools.sh list-learnings`. Show the numbered list as is, or say there are none. Mention that "forget <n>" removes one.
4. Forget intent with a number: run `bash ~/.claude/habits/bin/habit-tools.sh forget-learning <n>`, then show the list again.
5. Otherwise report the preloaded state in one or two plain sentences. If prompts are waiting, mention that the distill habit turns them into habits.
