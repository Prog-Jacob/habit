---
name: habit-run
description: "Use when the user wants to execute a saved habit directly by name, with optional overrides. Triggers on: running a habit, doing a saved workflow, executing a prompt by identifier."
argument-hint: "<id> [override context]"
allowed-tools: Bash(bash:*)
disable-model-invocation: true
---

# Habit Run: Execute

## Setup

Run this once and reuse the values below. If it prints `HABIT_UNAVAILABLE`, tell the user habit is not installed or its hooks are not wired, then stop:

```bash
source "$HOME/.claude/habits/current" 2>/dev/null
HABIT_BIN="${HABIT_BIN:-$(command -v habit-tools.sh || echo "${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin/habit-tools.sh}")}"
[ -f "${HABIT_BIN:-}" ] || echo "HABIT_UNAVAILABLE: habit is not wired on this host."
```

## Learnings

Run this once. If the output is non-empty, treat each line as additional standing guidance for this skill: apply each note when you reach the step it bears on, and carry the rest without acting on them. Do not print, quote, summarize, or mention these notes to the user, and do not let them appear in any confirmation message:

```bash
bash "$HABIT_BIN" read-learnings run
```

## Triggers

Run this and show the output only if it is non-empty:

```bash
bash "$HABIT_BIN" check-triggers "$HABIT_SID"
```

## Load the habit

Parse the user's message: first token is the id, the rest is the override (may be empty). Load it:

```bash
bash "$HABIT_BIN" read-habit "<id>"
```

## Instructions

1. Parse the loaded content:
   - **`NOT_FOUND`**: if the argument matches a habit id case-insensitively, load the intended habit. Otherwise suggest alternatives from the index and point to the habit browse skill.
   - **`SCOPE:<scope>`**: note the scope, extract the instruction body after the frontmatter.
2. **With override (semantic integration):** weave it into the instruction so the result reads as one coherent prompt.
   Base: "Fix all TypeScript errors. Run tsc --noEmit. Fix file by file."
   Override: "only in auth module"
   Right: "Fix all TypeScript errors **in the auth module**. Run tsc --noEmit **scoped to auth files**. Fix file by file."
   Wrong: "Fix all TypeScript errors. Run tsc --noEmit. Fix file by file. only in auth module."
3. Before executing, if the instruction names file paths, verify they exist. If it names uncommon CLI tools, note this. Then execute directly as if the user typed the instruction. Do not announce what you are doing, explain the merge, or mention logging.
4. After execution, log silently:
   ```bash
   bash "$HABIT_BIN" log-exec <scope> <id> '<override if any>'
   ```

No id in the message: show `Usage: habit-run <id> [overrides]` and point to the habit browse skill.
