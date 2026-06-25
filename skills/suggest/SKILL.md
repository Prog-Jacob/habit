---
name: habit-suggest
description: "Use when the user wants to apply relevant habits to their request without naming them individually. Triggers on: suggest habits, apply habits, help with [task] using habits."
argument-hint: "<request>"
allowed-tools: Bash(bash:*)
---

# Habit Suggest: Surface & Apply

## Setup

Run this once and reuse the values below. If it prints `HABIT_UNAVAILABLE`, tell the user habit is not installed or its hooks are not wired, then stop:

```bash
source "$HOME/.claude/habits/current" 2>/dev/null
HABIT_BIN="${HABIT_BIN:-$(command -v habit-tools.sh || echo "${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin/habit-tools.sh}")}"
[ -f "${HABIT_BIN:-}" ] || echo "HABIT_UNAVAILABLE: habit is not wired on this host."
```

## Triggers

Run this and show the output only if it is non-empty:

```bash
bash "$HABIT_BIN" check-triggers "$HABIT_SID"
```

## Index (active)

Run this and use the output:

```bash
bash "$HABIT_BIN" read-index merged active
```

## Instructions

1. Treat the user's message as the request. Empty: show `Usage: habit-suggest <request>` and point to the habit browse skill.
2. Score each non-archived habit for relevance using id, tags, description. Select those that meaningfully improve how the request is addressed. Skip tangential ones.
3. If none are relevant, address the request directly without ceremony.
4. Load all relevant habits in one call:
   ```bash
   bash "$HABIT_BIN" read-habit <id1> <id2> ...
   ```
   Output is delimited by `---HABIT:<id>---`. Each section starts with `SCOPE:<scope>`. Note the scope per habit. Extract the instruction body after the frontmatter.
5. Merge into a single directive. Where two conflict, the more narrowly scoped wins. Synthesize one coherent action, do not run them sequentially.
6. Execute the merged directive. Do not announce which habits are applied or describe internal operations.
7. After execution, log all applied habits in one call:
   ```bash
   bash "$HABIT_BIN" log-exec '[{"scope":"<scope>","id":"<id>","override":"<request summary, max 80 chars>"}, ...]'
   ```
