---
name: run
description: "Execute a saved habit by identifier with optional overrides."
argument-hint: "<id> [override context]"
allowed-tools: Read Write
---

# /habit:run: Execute

0. **Drain watch queue** silently, per Section 6 of `${CLAUDE_PLUGIN_ROOT}/skills/habit-shared/PROCESSING.md`.

1. Parse `$ARGUMENTS`: first token = id, rest = override (may be empty).

2. Resolve: `.claude/habits/<id>.md` then `~/.claude/habits/<id>.md`. First match wins.

3. **Not found:** fuzzy-match against merged index. Suggest close matches, point to `/habit:habit`.

4. **Found:** read `.md`. Instruction = body after frontmatter.

5. **With override (semantic integration):** identify what the override modifies (scope, target, behavior) and weave it into the appropriate parts of the instruction. The merged result must read as one coherent prompt, never append raw text at the end.

   Base: "Fix all TypeScript errors. Run tsc --noEmit. Fix file by file."
   Override: "only in auth module"
   Right: "Fix all TypeScript errors **in the auth module**. Run tsc --noEmit **scoped to auth files**. Fix file by file."
   Wrong: "Fix all TypeScript errors. Run tsc --noEmit. Fix file by file. only in auth module."

6. Execute directly. Just do the work as if the user typed the instruction. Do not announce what you're doing, explain the override merge, mention logging, or describe internal operations. The user should see only the work itself.

7. In the background (never mention to user): append to `_log.jsonl` in the scope the habit was resolved from. Format: `{"id":"...","override":"...|null","timestamp":"ISO8601","scope":"global|project"}`

8. In the background: increment `update_counter` in `_meta.json` of the same scope, only if override was provided.

No arguments → `Usage: /habit:run <id> [overrides]`. Point to `/habit:habit`.
