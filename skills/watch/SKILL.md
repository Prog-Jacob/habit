---
name: habit-watch
description: "Use when the user wants to check habit's health, pause or resume prompt capture, snooze the distill reminder, or see and remove what habit has learned about its own skills. Triggers on: watch status, habit status, stop watching, pause capture, resume capture, snooze reminders, list learnings, forget a learning."
argument-hint: "[status | off [hours] | on | snooze [days] | forget <n>]"
allowed-tools: Bash(bash:*)
disable-model-invocation: true
---

# Habit Watch: Status and Capture Control

Capture is on by default: each prompt goes to a local inbox that the distill habit reads. When the inbox is due for distill, a new session shows one reminder a day. Watch has no learnings overlay, by design.

## Preload

Run this once before anything else:

```bash
bash ~/.claude/habits/bin/habit-tools.sh preload watch
```

If the command is missing, tell the user habit's hooks have not run yet and to start a new session, then stop.

The output is the status report: the running version and installed copies, v2 leftovers, capture state and last capture per host, the backlog and whether distill is due, the last distill, habit counts, the rule budget, the numbered learnings, and the integrity checks. A line that starts with `WARN:` or `FAIL:` needs the user's attention.

## Routing

1. Pause intent (off, stop, pause, disable), with optional hours: run `bash ~/.claude/habits/bin/habit-tools.sh watch off [hours]` (8 hours when none are given). Confirm when capture resumes on its own.
2. Resume intent (on, start, resume): run `bash ~/.claude/habits/bin/habit-tools.sh watch on`. Confirm "Capture resumed."
3. Snooze intent (snooze, stop reminding, quiet the distill reminder), with optional days: run `bash ~/.claude/habits/bin/habit-tools.sh watch snooze [days]` (7 days when none are given). Confirm the date the reminder returns.
4. Forget intent with a number: run `bash ~/.claude/habits/bin/habit-tools.sh forget-learning <n>`, then run `bash ~/.claude/habits/bin/habit-tools.sh list-learnings` and show the new list.
5. Learnings intent (learnings, what have you learned): show the numbered learnings from the report as is, or say there are none. Mention that "forget <n>" removes one.
6. A fresh check later in the conversation: run `bash ~/.claude/habits/bin/habit-tools.sh status`.
7. Otherwise, summarize the report in a few plain lines: capture state, the backlog, and whether distill is due. Repeat every `WARN:` and `FAIL:` line with its fix. If distill is due, mention that the distill habit turns the prompts into habits.
