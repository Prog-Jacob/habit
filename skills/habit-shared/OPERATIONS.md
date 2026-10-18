# Habit Operations Reference

All habit data goes through the habit CLI. Invoke every command as `bash ~/.claude/habits/bin/habit-tools.sh <command> ...`. Do not use Read, Write, Glob, or Grep on habit files directly. Project scope resolves from the current directory, or from `HABIT_PROJECT_DIR=<dir>` placed before the command.

## Habits

- **Read habit(s):** `read-habit <id> [<id2> ...]`. One id returns `SCOPE:<scope>` and the content. Several ids return `---HABIT:<id>---` delimited sections. A missing id returns `NOT_FOUND`.
- **Write a habit:** `write-habit <scope> <id> '<frontmatter+body>'` (or pipe the content on stdin). It rejects an invalid id, a frontmatter id that differs from `<id>`, a missing description, a `kind` other than `rule` or `procedure`, and a rule whose body (the text after the frontmatter) is longer than 600 characters.
- **Delete a habit:** `delete-habit <scope> <id>`.
- **Read the index:** `read-index <merged|global|project> [active]`. With `active`: non-archived entries only, compact (id, tags, description, scope, and kind when set).
- **Standing rules:** `preload rules` prints what every session loads: the active rules (global ones first, then the current project's, which win a conflict), a one-line index of procedures, the distill due line when due, a count of unclassified habits, and a final `INJECTED: <ids>` line. The output stays within 8,000 characters. Project rules get the budget first, and rules that do not fit are listed by id on a `Rules not loaded (budget):` line.
- **Context files:** `context-files [project root]` prints `~/.claude/CLAUDE.md`, the project's `CLAUDE.md` and `AGENTS.md`, and its Claude memory index, each headed `---FILE:<path>---` and capped at 4,000 characters. The root defaults to the current project.
- **Log execution:** `log-exec '[{"scope":"...","id":"...","note":"..."}]' <session id>`. Leave `note` out unless the user gave an explicit override.

## Distill runs

- **Claim the inbox:** `claim`. Prints `EMPTY`, or `RUN <id>`, an optional `REMAINING <n>`, and the claimed prompts grouped by project. It snapshots the habits first.
- **Finish a run:** `finish <run>`. Call it only after every write of the run succeeded. An unfinished run is claimed again next time.
- **Snapshot without claiming:** `snapshot [label]`. Takes a distill run snapshot of the global and current project habits and the learnings, and prints `RUN <id>`. Use it when a run writes without claiming prompts, so `undo` still covers it.
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
kind: <rule|procedure>
last_executed: <ISO 8601, optional>
---

## Instruction

<structured instruction body>
```

A rule's body is the rule text itself, with no `## Instruction` heading, at most 600 characters.

`last_executed` is derived from the usage log. A frontmatter value only seeds it: preserve the line on edit, and never write or add it.
