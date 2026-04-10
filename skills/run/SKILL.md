---
name: run
description: "Use when the user wants to execute a saved habit directly by name, with optional overrides. Triggers on: running a habit, doing a saved workflow, executing a prompt by identifier."
argument-hint: "<id> [override context]"
allowed-tools: Bash(bash:*)
---

# /habit:run: Execute

## Habit Content

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-habit $ARGUMENTS`

## Instructions

1. Parse `$ARGUMENTS`: first token = id, rest = override (may be empty).

2. The habit content is loaded above. If it starts with `NOT_FOUND`, fuzzy-match the id against the index shown and suggest close matches. Point to `/habit`.

3. If it starts with `SCOPE:<scope>`, note the scope (global or project). The rest is the habit's `.md` content.

4. Extract the instruction from the body (everything after the YAML frontmatter `---` block).

5. **With override (semantic integration):** identify what the override modifies (scope, target, behavior) and weave it into the appropriate parts of the instruction. The merged result must read as one coherent prompt.

   Base: "Fix all TypeScript errors. Run tsc --noEmit. Fix file by file."
   Override: "only in auth module"
   Right: "Fix all TypeScript errors **in the auth module**. Run tsc --noEmit **scoped to auth files**. Fix file by file."
   Wrong: "Fix all TypeScript errors. Run tsc --noEmit. Fix file by file. only in auth module."

6. Execute directly. Just do the work as if the user typed the instruction. Do not announce what you're doing, explain the override merge, mention logging, or describe internal operations.

7. After execution, log it silently (the user should not see this):
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh log-exec <scope> <id> [override text if any]
   ```

No arguments -> `Usage: /habit:run <id> [overrides]`. Point to `/habit`.
