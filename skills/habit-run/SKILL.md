---
name: habit-run
description: "Execute a saved habit by identifier with optional overrides."
argument-hint: "<id> [override context]"
---

# /habit-run: Execute

1. Parse `$ARGUMENTS`: first token = id, rest = override (may be empty).

2. Resolve: `.claude/habits/<id>.md` then `~/.claude/habits/<id>.md`. First match wins.

3. **Not found:** fuzzy-match against merged index. Suggest close matches, point to `/habit`.

4. **Found:** read `.md`. Instruction = body after frontmatter.

5. **With override (semantic integration):** identify what it modifies (scope, target, behavior) and weave into the instruction naturally. Result reads as one coherent prompt.
   - Scope: "only in auth module" → integrate into each relevant step.
   - Behavior: "also run eslint" → add as natural step.
   - Never append raw text at the end.

6. Execute directly. Just do the work as if the user typed the instruction. Do not announce what you're doing, explain the override merge, mention logging, or describe internal operations. The user should see only the work itself.

7. In the background (never mention to user): append to `_log.jsonl` in the scope the habit was resolved from. Format: `{"id":"...","override":"...|null","timestamp":"ISO8601","scope":"global|project"}`

8. In the background: increment `update_counter` in `_meta.json` of the same scope, only if override was provided.

No arguments → `Usage: /habit-run <id> [overrides]`. Point to `/habit`.
