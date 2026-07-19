---
name: habit-run
description: "Use when the user wants to execute a saved habit directly by name, with optional overrides. Triggers on: running a habit, doing a saved workflow, executing a prompt by identifier."
argument-hint: "<id> [override context]"
allowed-tools: Bash(bash:*)
disable-model-invocation: true
---

# Habit Run: Execute

## Preload

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh skill-preload run ${CLAUDE_SESSION_ID}`

Run this Setup block once and reuse the values below:

```bash
HABIT_SID_FILE=$(ls -t "$HOME/.claude/habits/sessions.d/"* 2>/dev/null | head -1)
source "${HABIT_SID_FILE:-$HOME/.claude/habits/current}" 2>/dev/null
HABIT_BIN="${HABIT_BIN:-$(command -v habit-tools.sh || echo "${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin/habit-tools.sh}")}"
[ -f "${HABIT_BIN:-}" ] || echo "HABIT_UNAVAILABLE: habit is not wired on this host."
```

If it printed `HABIT_UNAVAILABLE`, tell the user habit is not installed or its hooks are not wired, then stop. Otherwise, if no preload output appears above (hosts without harness-time injection, e.g. Cursor), run `bash "$HABIT_BIN" skill-preload run "$HABIT_SID"` once.

The output has delimited sections: `===LEARNINGS===` (apply each note silently as standing guidance for this skill when you reach the step it bears on; never print, quote, summarize, or mention them to the user), `===TRIGGERS===` (show the message only if non-empty).

## Load the habit

Parse the user's message: first token is the id, the rest is the override (may be empty). Load it:

```bash
bash "$HABIT_BIN" read-habit "<id>"
```

## Instructions

1. Parse the loaded content:
   - **`NOT_FOUND`**: suggest alternatives from the index and point to the habit browse skill. Only if the index clearly contains the habit the user meant under a different name or id (a naming or routing mismatch, not a habit that simply does not exist), log it once before suggesting:
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
