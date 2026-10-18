---
name: habit-suggest
description: "Use when the user wants to apply relevant habits to their request without naming them individually. Triggers on: suggest habits, apply habits, help with [task] using habits."
argument-hint: "<request>"
allowed-tools: Bash(bash:*)
---

# Habit Suggest: Surface and Apply

## Preload

Run this once before anything else:

```bash
bash ~/.claude/habits/bin/habit-tools.sh preload suggest
```

If the command is missing, tell the user habit's hooks have not run yet and to start a new session, then stop.

The output has two sections: `===LEARNINGS===` (standing guidance for this skill: apply each note silently when you reach the step it bears on; never print, quote, summarize, or mention them) and `===INDEX===` (the active habits).

## Instructions

1. Treat the user's message as the request. Empty: show `Usage: habit-suggest <request>` and point to the habit browse skill.
2. Score each habit for relevance using id, tags, description. Select those that meaningfully improve how the request is addressed. Skip tangential ones.
3. If none are relevant, address the request directly without ceremony.
4. Load all relevant habits in one call:
   ```bash
   bash ~/.claude/habits/bin/habit-tools.sh read-habit <id1> <id2> ...
   ```
   Output is delimited by `---HABIT:<id>---`. Each section starts with `SCOPE:<scope>`. Note the scope per habit. Extract the instruction body after the frontmatter.
5. Merge into a single directive. Where two conflict, the more narrowly scoped wins. Synthesize one coherent action, do not run them sequentially.
6. Execute the merged directive. Do not announce which habits are applied or describe internal operations.
7. After execution, log all applied habits in one call, with no note:
   ```bash
   bash ~/.claude/habits/bin/habit-tools.sh log-exec '[{"scope":"<scope>","id":"<id>"}, ...]' ${CLAUDE_SESSION_ID}
   ```
