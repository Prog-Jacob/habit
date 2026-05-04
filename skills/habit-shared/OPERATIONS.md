# Habit Operations Reference

All habit data goes through `habit-tools.sh`. Do not use Read, Write, Glob, or Grep on habit files directly. If you need data that isn't preloaded, call the appropriate command below.

## Commands

- **Read a habit:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-habit <id>`
- **Write a habit:** pipe full content (frontmatter + body) to `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh write-habit <scope> <id>`
- **Log an execution:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh log-exec <scope> <id> '<override>'`. Always call after running a habit. Single-quote the override to prevent shell metacharacter interpretation. Without override, only updates `last_executed`. With override, also appends to the override log.
- **Self-heal:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh self-heal <scope>`
- **Reset meta (after deep distill):** zero the update counter and set last deep timestamp. `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh reset-meta <scope>`
- **Prune log (after deep distill):** truncate to last 25 entries. `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh prune-log <scope>`

## Query commands

Read-only. Most are pre-loaded in skills that need them.

- **Read index:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-index <merged|global|project>`
- **Read metadata:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-meta <global|project>`
- **Read execution log:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-log`
- **Read pending sessions:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-pending-distill`
- **Read transcript:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-transcript <path>`
- **Read prompt count:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-prompt-count <session_id>`
- **Reset prompt count:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh reset-prompt-count <session_id>`
- **Clear pending sessions:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh clear-pending-distill`
- **Check triggers:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh check-triggers <session_id>`
- **Should deep:** `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh should-deep`

## Error handling

If any command exits non-zero, stop and report the error to the user, unless the step explicitly says to skip failures.

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
