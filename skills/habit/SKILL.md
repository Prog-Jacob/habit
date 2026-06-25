---
name: habit
description: "Use when the user mentions habits, saved prompts, reusable workflows, repeated commands, or their prompt inventory. Triggers on browsing, searching, listing, or selecting habits. Routes to the run, edit, suggest, watch, and distill habits."
argument-hint: "[search query]"
allowed-tools: Bash(bash:*)
---

# Habit: Entry Point & Browse

## Setup

Run this once and reuse the values below. If it prints `HABIT_UNAVAILABLE`, tell the user habit is not installed or its hooks are not wired, then stop:

```bash
source "$HOME/.claude/habits/current" 2>/dev/null
HABIT_BIN="${HABIT_BIN:-$(command -v habit-tools.sh || echo "${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin/habit-tools.sh}")}"
[ -f "${HABIT_BIN:-}" ] || echo "HABIT_UNAVAILABLE: habit is not wired on this host."
```

## Triggers

Run this and show the output only if it is non-empty:

```bash
bash "$HABIT_BIN" check-triggers "$HABIT_SID"
```

## Routing

- **Browsing/searching/listing** handle below.
- **Viewing full details** guide the user to the edit habit by id (it shows full content when no changes are given).
- **Creating or editing** guide to the edit habit.
- **Running a specific habit** guide to the run habit.
- **Applying relevant habits to a request** guide to the suggest habit.
- **Watching/observing** guide to the watch habit.
- **Extracting/sweeping** guide to the distill habit.
- **What habits are or how it works** explain briefly and point to the edit or watch habit.

After routing, stop. Do not also run the Browse flow below.

## Index (merged, project shadows global)

Run this and use the output:

```bash
bash "$HABIT_BIN" read-index merged
```

## Browse & Select

1. Empty message: list all. Non-empty: treat it as a search query.
2. Each entry has a `scope` field (`global` or `project`). Show `[G]`/`[P]`. Exclude archived.
3. If searching, fuzzy-match against id, tags, description. If nothing matches, say so and suggest creating one.
4. Numbered list, one line each: `N. [scope] id    tags    description`. Never mention archived entries.
5. After the list:
   > Pick a number or name to run, add context for an override (e.g. "1 only in auth"), or say "edit N" to modify.
6. When the user picks one, guide them to run that habit by id.
7. Empty inventory:
   > No habits yet. Create one with the edit habit, or start watching with the watch habit.
