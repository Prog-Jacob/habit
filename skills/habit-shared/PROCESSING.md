---
name: habit-shared
description: "Shared processing rules for Habit. Not user-facing."
user-invocable: false
disable-model-invocation: true
---

# Habit Processing Rules

All habit commands that create, modify, or inspect habits follow these rules. Do not announce internal operations to the user. Show only the final result.

## Operations

All file operations go through `habit-tools.sh`. Never use the Read or Write tools on habit files directly.

- **Read a habit:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-habit <id>`
- **Write a habit:** pipe full content (frontmatter + body) to `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh write-habit <scope> <id>`
- **Log an execution:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh log-exec <scope> <id> [override]`
- **Self-heal:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh self-heal <scope>`

## 1. Interpretation

When capturing a habit from any source:

- **Extract the principle, not the instance.** Strip session-specific details (file names, line numbers). Instruction must work in any future context.
- **Expand terse instructions into clear steps**, but only steps the user actually said or directly implied. Every step in the output must trace back to something the user wrote. If you cannot point to where the user expressed or implied a step, do not include it.
- **Tighten verbose instructions** without losing intent or steps.
- **Infer 1-3 tags.** Lowercase singular nouns (`typescript` not `TS`).
- **Generate description.** Max 120 chars, starts with verb.
- **Instruction must be self-contained.** No references to conversation. Use "in the specified scope" for overrideable targets.

## 2. Deduplication

Compare new candidate against existing habits by intent/outcome, not string matching. Use `read-habit <id>` to load existing habits for comparison.

- **>80% overlap** → Skip. Tell user it's already covered.
- **50-80%** → Merge into existing. Preserve intent from both. Update `updated` timestamp.
- **<50%, related domain** → Create new. Ensure tags distinguish them.

## 3. Override Patterns

From the execution log: group by id, collect overrides, normalize (lowercase, trim). **3+ similar = pattern:**

- Scope-narrowing → create variant (e.g., `fix-types-auth`).
- Behavior-adding → update base habit.

## 4. Scope Detection

- References relative paths, project scripts, or project config → `project` → `.claude/habits/`
- Generic → `global` → `~/.claude/habits/`

## 5. Habit File Format

```
---
id: <id>
tags: [tag1, tag2]
description: <one-line, max 120 chars, starts with verb>
scope: <global|project>
created: <ISO 8601>
updated: <ISO 8601>
archived: false
---

## Instruction

<structured instruction body>
```

## 6. Queue Drain

**Only runs during `/habit:watch off` and `/habit:distill`.** Not on `/habit` or `/habit:run`. Those are fast paths.

If `/tmp/habit-watch-queue-${CLAUDE_SESSION_ID}` exists and is non-empty, process it:

1. Read the file. Prompts are separated by `---HABIT_SEPARATOR---`.
2. Classify each: reusable or one-off (same criteria as Section 1).
3. For reusable prompts, apply interpretation, dedup, scope detection (Sections 1-4).
4. Write each via `write-habit`.
5. Truncate the queue file after processing.

## 7. Self-Healing

Run `self-heal <scope>` to deterministically rebuild the index from `.md` frontmatter and ensure `settings.local.json` exists with defaults.

Trigger when: index is missing or corrupt, orphaned entries detected, or after manual edits to habit files.
