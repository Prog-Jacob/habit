# Habit Operations Reference

All habit data goes through `habit-tools.sh`. Do not use Read, Write, Glob, or Grep on habit files directly. If you need data that isn't preloaded, call the appropriate command below.

## Commands

- **Read a habit:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-habit <id>`
- **Write a habit:** pipe full content (frontmatter + body) to `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh write-habit <scope> <id>`
- **Log an execution:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh log-exec <scope> <id> '<override>'`. Always call after running a habit. Single-quote the override to prevent shell metacharacter interpretation. Without override, only updates `last_executed`. With override, also appends to the override log.
- **Self-heal:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh self-heal <scope>`
- **Reset meta (after deep distill):** zero the update counter and set last deep timestamp. `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh reset-meta <scope>`
- **Prune log (after deep distill):** truncate to last 25 entries. `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh prune-log <scope>`

## Habit File Format

```
---
id: <id>
tags: [tag1, tag2]
description: <one-line, max 120 chars, starts with verb>
scope: <global|project>
created: <ISO 8601>
updated: <ISO 8601>
archived: false
last_executed: <ISO 8601, system-managed, preserve on edit>
---

## Instruction

<structured instruction body>
```

## Auto-Triggers

Trigger flags are preloaded in the skill above. `none` means proceed normally. `pending`, `distill`, or `deep` means maintenance is available: after your primary task, suggest `/habit:distill` to the user. (Does not apply inside `/habit:distill`.)
