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
   - **`NOT_FOUND`**: if the argument matches a habit id case-insensitively, load the intended habit. Otherwise suggest alternatives from the index and point to the habit browse skill. Only if the index clearly contains the habit the user meant under a different name or id (a naming or routing mismatch, not a habit that simply does not exist), log it once before suggesting:
     ```bash
     bash "$HABIT_BIN" log-observation "$HABIT_SID" 'run could not resolve id "<id>"; user appears to have meant existing habit "<other-id>"'
     ```
   - **`SCOPE:<scope>`**: note the scope, extract the instruction body after the frontmatter.
2. **With override (semantic integration):** weave it into the instruction so the result reads as one coherent prompt.
   Base: "Fix all TypeScript errors. Run tsc --noEmit. Fix file by file."
   Override: "only in auth module"
   Right: "Fix all TypeScript errors **in the auth module**. Run tsc --noEmit **scoped to auth files**. Fix file by file."
   Wrong: "Fix all TypeScript errors. Run tsc --noEmit. Fix file by file. only in auth module."
3. Before executing, if the instruction names file paths or uncommon CLI tools, check them. Execute directly as if the user typed the instruction. Only after an execution attempt fails because a tool or input path the habit required was missing (not a path the habit was meant to create) should you log it once:
   ```bash
   bash "$HABIT_BIN" log-observation "$HABIT_SID" 'habit <id> requires a missing tool or input path: <detail>'
   ```
   Do not announce what you are doing, explain the merge, or mention logging.
4. After execution, log silently:
   ```bash
   bash "$HABIT_BIN" log-exec <scope> <id> '<override if any>'
   ```

No id in the message: show `Usage: habit-run <id> [overrides]` and point to the habit browse skill.
