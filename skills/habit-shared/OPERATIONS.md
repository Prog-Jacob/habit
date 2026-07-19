# Habit Operations Reference

All habit data goes through `habit-tools.sh`. Invoke every command as `bash "$HABIT_BIN" <subcommand> ...`. Do not use Read, Write, Glob, or Grep on habit files directly. If you need data that isn't preloaded, call the appropriate command below.

## Commands

- **Read habit(s):** `read-habit <id> [<id2> ...]`. Single ID returns `SCOPE:<scope>` + content. Multiple IDs returns `---HABIT:<id>---` delimited sections.
- **Write a habit:** `write-habit <scope> <id> '<frontmatter+body>'` (or pipe content via stdin)
- **Log execution:** `log-exec <scope> <id> '<override>'` for a single habit, or `log-exec '[{"scope":"...","id":"...","override":"..."}]'` for batch (one state write per scope).
- **Self-heal:** `self-heal <scope>`
- **Reset meta (after deep distill):** zero the update counter and set last deep timestamp. `reset-meta <scope>`
- **Prune log (after deep distill):** truncate to last 25 entries. `prune-log <scope>`

## Query commands

Read-only. Most are pre-loaded in skills that need them.

- **Read index:** `read-index <merged|global|project> [active]`. With `active`: non-archived entries only, compact format (id, tags, description, scope).
- **Read metadata:** `read-meta <global|project>`
- **Read execution log:** `read-log`
- **Read pending sessions:** `read-pending-distill`
- **Read transcript:** `read-transcript <path> [<path2> ...]`. Single path returns content directly. Multiple paths returns `---SESSION:<path>---` delimited sections (skips missing files).
- **List new sessions:** `list-new-sessions "$HABIT_SID"`. Returns file paths of new or modified project sessions (not yet distilled or modified since last distill); the sid excludes the live session's transcript. **(Only in distill Project branch.)**
- **Read prompt count:** `read-prompt-count <session_id>`
- **Check triggers:** `check-triggers <session_id>`

## Cleanup commands

- **Reset prompt count:** `reset-prompt-count <session_id>`
- **Clear pending sessions:** `clear-pending-distill`
- **Mark sessions distilled:** `mark-sessions-distilled <path1> [<path2> ...]`. Records file mtimes as watermarks for incremental project distill.
- **Clear observations:** `clear-observations`

## Observation commands

During any operation, if you encounter friction that stems from the plugin itself, log it. These are signals every user would independently discover: a skill instruction that's ambiguous, a command that returns misleading output, routing that sends to the wrong skill, processing rules that miss an edge case, or transcript extraction that includes noise or drops real content.

Do not log user preferences (those are habits), one-off environment issues, or general LLM limitations.

- **Log observation:** `log-observation <session_id> '<signal>'`. Single-quote the signal.
- **Read observations:** `read-observations`

## Output discipline

User-facing output should be only the message itself. Do not mention internal operations, bash commands, or file paths.

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
