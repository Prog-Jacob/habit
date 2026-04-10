---
name: habit-shared
description: "Shared processing rules for Habit. Not user-facing."
user-invocable: false
disable-model-invocation: true
---

# Habit Processing Rules

## 1. Interpretation

When capturing a habit from any source:

- **Extract the principle, not the instance.** Strip session-specific details (file names, line numbers). Instruction must work in any future context.
- **Expand terse instructions into clear steps**, only steps the user expressed or clearly implied. Do not inject domain expertise or best practices the user didn't mention.
- **Tighten verbose instructions** without losing intent or steps.
- **Infer 1-3 tags.** Lowercase singular nouns (`typescript` not `TS`).
- **Generate description.** Max 120 chars, starts with verb.
- **Instruction must be self-contained.** No references to conversation. Use "in the specified scope" for overrideable targets.

## 2. Deduplication

Compare new candidate against existing habits by intent/outcome, not string matching:

- **>80% overlap** → Skip. Tell user it's already covered.
- **50-80%** → Merge into existing. Preserve intent from both. Update `updated` timestamp.
- **<50%, related domain** → Create new. Ensure tags distinguish them.

## 3. Override Patterns

From `_log.jsonl`: group by id, collect overrides, normalize (lowercase, trim). **3+ similar = pattern:**

- Scope-narrowing → create variant (e.g., `fix-types-auth`).
- Behavior-adding → update base habit.

## 4. Scope Detection

- References relative paths, project scripts, or project config → `project` → `.claude/habits/`
- Generic → `global` → `~/.claude/habits/`

## 5. Write Sequence

Pipe the complete habit file (YAML frontmatter + instruction body) to:

```
bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh write-habit <scope> <id>
```

This atomically writes the `.md` file, updates `_index.json`, and increments `update_counter` in `_meta.json`. Creates missing dirs/files as needed.

The file content must follow this format:

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
4. Write each new/updated habit via: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh write-habit <scope> <id>`
5. Truncate the queue file after processing.

## 7. Self-Healing

Run: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh self-heal <scope>`

This deterministically rebuilds `_index.json` from `.md` frontmatter, creates missing `_meta.json` and `_log.jsonl` with defaults. No Claude reasoning involved. The script handles it.

Trigger self-heal when:

- Index is missing or corrupt
- Orphaned entries detected
- After manual edits to habit files
