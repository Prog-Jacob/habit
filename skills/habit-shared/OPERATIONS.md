# Habit Operations Reference

All habit data goes through the habit CLI. Invoke every command as `bash ~/.claude/habits/bin/habit-tools.sh <command> ...`. Do not use Read, Write, Glob, or Grep on habit files directly. Project scope resolves from the current directory, or from `HABIT_PROJECT_DIR=<dir>` placed before the command.

## Habits

- **Read habit(s):** `read-habit <id> [<id2> ...]`. One id returns `SCOPE:<scope>` and the content. Several ids return `---HABIT:<id>---` delimited sections. A missing id returns `NOT_FOUND`.
- **Write a habit:** `write-habit <scope> <id> '<frontmatter+body>'` (or pipe the content on stdin). It rejects an invalid id, a frontmatter id that differs from `<id>`, and a missing description.
- **Delete a habit:** `delete-habit <scope> <id>`.
- **Read the index:** `read-index <merged|global|project> [active]`. With `active`: non-archived entries only, compact (id, tags, description, scope).
- **Log execution:** `log-exec '[{"scope":"...","id":"...","note":"..."}]' <session id>`. Leave `note` out unless the user gave an explicit override.

## Distill runs

- **Claim the inbox:** `claim`. Prints `EMPTY`, or `RUN <id>`, an optional `REMAINING <n>`, and the claimed prompts grouped by project. It snapshots the habits first.
- **Finish a run:** `finish <run>`. Call it only after every write of the run succeeded. An unfinished run is claimed again next time.
- **Undo the last run:** `undo`. Restores the snapshot, lists the files it changed, and queues that run's prompts again. An undo can itself be undone.

## Learnings

- **Write a learning:** `write-learning <target> '<rule>' '<origin>'`, with target `habit`, `suggest`, `edit`, `distill`, or `global`.
- **List learnings:** `list-learnings` (numbered).
- **Forget a learning:** `forget-learning <n>`, or `watch forget <n>`.

## Monitoring

- **Status:** `status` (same as `watch`). Prints the health report: version, installed copies, capture, backlog, whether distill is due, habit counts, rule budget, learnings, and integrity checks. It exits non-zero when an integrity check fails.
- **Pause capture:** `watch off [hours]` (8 hours by default). `watch on` resumes it.
- **Snooze the distill reminder:** `watch snooze [days]` (7 days by default).

## Environment

- **Plugin context:** `env-context` prints `source` in a habit working tree, else `installed`.

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
last_executed: <ISO 8601, optional>
---

## Instruction

<structured instruction body>
```

`last_executed` is derived from the usage log. A frontmatter value only seeds it: preserve the line on edit, and never write or add it.
