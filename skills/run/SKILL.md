---
name: run
description: "Use when the user wants to execute a saved habit directly by name, with optional overrides. Triggers on: running a habit, doing a saved workflow, executing a prompt by identifier."
argument-hint: "<id> [override context]"
allowed-tools: Bash(bash:*)
---

# /habit:run: Execute

## Triggers

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh check-triggers ${CLAUDE_SESSION_ID}`

If triggers are not `none`, add after your response: "Habit maintenance available. Run `/habit:distill` to process."

## Habit Content

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-habit "$1"`

## Instructions

1. Parse `$ARGUMENTS`: first token = id, rest = override (may be empty).

2. Parse the loaded content:
   - **`NOT_FOUND`**: fuzzy-match the id against the index and suggest alternatives. Point to `/habit`.
   - **`SCOPE:<scope>`**: note the scope, extract the instruction body (everything after the YAML frontmatter `---` block).

3. **With override (semantic integration):** identify what the override modifies (scope, target, behavior) and weave it into the appropriate parts of the instruction. The merged result must read as one coherent prompt.

   Base: "Fix all TypeScript errors. Run tsc --noEmit. Fix file by file."
   Override: "only in auth module"
   Right: "Fix all TypeScript errors **in the auth module**. Run tsc --noEmit **scoped to auth files**. Fix file by file."
   Wrong: "Fix all TypeScript errors. Run tsc --noEmit. Fix file by file. only in auth module."

4. Execute directly. Just do the work as if the user typed the instruction. Do not announce what you're doing, explain the override merge, mention logging, or describe internal operations.

5. After execution, log it silently (the user should not see this):
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh log-exec <scope> <id> '<override if any>'
   ```

No arguments -> `Usage: /habit:run <id> [overrides]`. Point to `/habit`.
