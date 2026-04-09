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

1. Write `<id>.md` with YAML frontmatter (id, tags, description, scope, created, updated, archived: false) and instruction body under `## Instruction`.
2. Update `_index.json` (add/update entry).
3. Increment `update_counter` in `_meta.json`.

Create missing dirs/files as needed.

## 6. Self-Healing

On read: missing `_index.json` → rebuild from `.md` frontmatter. Missing `_meta.json` → create with defaults. Missing `_log.jsonl` → create empty. Orphaned index entry → remove. `.md` without entry → add. Corrupt frontmatter → skip, warn.
