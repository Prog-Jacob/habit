---
name: habit-shared
description: "Shared processing rules for Habit. Not user-facing."
user-invocable: false
disable-model-invocation: true
---

# Habit Processing Rules

All habit commands that create, modify, or inspect habits follow these rules. Do not announce internal operations to the user. Show only the final result.

## 1. Interpretation

When capturing a habit from any source:

- **Extract the principle, not the instance.** Strip session-specific details (file names, line numbers). Instruction must work in any future context.
- **Expand terse instructions into clear steps**, but only steps the user actually said or directly implied. Every step in the output must trace back to something the user wrote. If you cannot point to where the user expressed or implied a step, do not include it.
- **Tighten verbose instructions** without losing intent or steps.
- **Infer 1-3 tags.** Lowercase singular nouns (`typescript` not `TS`).
- **Generate description.** Max 120 chars, starts with verb.
- **Instruction must be self-contained.** No references to conversation. Use "in the specified scope" for overrideable targets.

## 2. Deduplication

Compare new candidate against existing habits by intent/outcome, not string matching. Use `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-habit <id>` to load existing habits for comparison.

- **>80% overlap** → Skip. Tell user it's already covered. If the user actually shows intent, create it.
- **50-80%** → Merge into existing. Preserve intent from both. Update `updated` timestamp.
- **<50%, related domain** → Create new. Ensure tags distinguish them.

## 3. Override Patterns

From the execution log: group by id, collect overrides, normalize (lowercase, trim). **3+ similar = pattern:**

- Scope-narrowing → create variant (e.g., `fix-types-auth`).
- Behavior-adding → update base habit.

## 4. Scope Detection

- References relative paths, project scripts, or project config → `project` → `.claude/habits/`
- Generic → `global` → `~/.claude/habits/`
