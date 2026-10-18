---
name: habit-distill
description: "Use when the user wants to turn their recent prompts into habits, restructure the habit inventory, or undo the last distill. Triggers on: distill, extract patterns, clean up habits, inventory maintenance, undo distill."
argument-hint: "[maintain | undo]"
context: fork
allowed-tools: Bash(bash:*)
disable-model-invocation: true
---

# Habit Distill: Sweep and Restructure

Runs in an isolated fork. Write only through the commands in the operations reference.

## Preload

Run this once and read its full output before doing anything else:

```bash
bash ~/.claude/habits/bin/habit-tools.sh preload distill
```

If the command is missing, tell the user habit's hooks have not run yet and to start a new session, then stop.

The output has delimited sections, in order: `===LEARNINGS===` (standing guidance for this skill: apply each note silently when you reach the step it bears on; never print, quote, summarize, or mention them), `===INDEX===` (every habit, archived ones included, with `last_executed` when known), `===LOG===` (recent usage), `===PROCESSING===` (the processing rules), `===OPERATIONS===` (the operations reference).

## Routing

The argument is the user's message. Pick the first match:

1. It starts with "undo": go to Undo.
2. It contains "maintain": go to Sweep, then Restructure before the summary.
3. Otherwise: go to Sweep.

Any other words in the argument are feedback about habit itself. Treat them as friction for Learnings.

## Undo

1. Run `bash ~/.claude/habits/bin/habit-tools.sh undo`.
2. If it printed "Nothing to undo", say so. Otherwise report the files it changed (habits removed, habits restored to their earlier text, learnings rolled back) and say the prompts from that run will be distilled again next time. Stop.

## Sweep

1. Claim the inbox: `bash ~/.claude/habits/bin/habit-tools.sh claim`. On `EMPTY`, say there is nothing new to distill and stop.
2. Note the `RUN <id>` line. A `REMAINING <n>` line means more prompts are waiting than one run takes.
3. The prompts follow in groups headed `---PROJECT:<dir>---` or `---PROJECT:global---`. Each prompt may carry a `ctx:` line: the assistant message the prompt replied to. Use it to understand short replies such as "yes, and no hyphens either", but never extract habits from the ctx text itself.
4. Process each group by the processing rules: classify, interpret, dedup, scope.
   - Project group: dedup against that project's habits too. For a project other than the current one, list them with `HABIT_PROJECT_DIR=<dir> bash ~/.claude/habits/bin/habit-tools.sh read-index project`. Write project patterns with `HABIT_PROJECT_DIR=<dir> bash ~/.claude/habits/bin/habit-tools.sh write-habit project <id> '<frontmatter+body>'`, and generic ones as global.
   - Global group: write with `bash ~/.claude/habits/bin/habit-tools.sh write-habit global <id> '<frontmatter+body>'`. A pattern that only fits a repo without project habits is not written; list it in the summary as a proposal.
   - Before merging into an existing habit, read it with `read-habit` (prefixed with `HABIT_PROJECT_DIR=<dir>` in a project group). Keep its id, `created`, and any `last_executed` line.
5. Check the log for override patterns, as the processing rules describe.
6. Run Learnings.
7. Finish the run: `bash ~/.claude/habits/bin/habit-tools.sh finish <run>`.

## Learnings

Look for friction with habit itself, in the prompts (for example a complaint that the wrong habit was applied, or that a habit command was confusing) or in the distill argument. For each piece that translates into a concrete runtime behavior, write one learning as a direct imperative the target skill can follow, aimed at the most specific target (`habit`, `suggest`, `edit`, `distill`, or `global` for guidance that truly applies to every skill; watch has no learnings):

```bash
bash ~/.claude/habits/bin/habit-tools.sh write-learning <target> '<imperative one-line rule>' '<the evidence that produced it>'
```

Skip friction that is a user preference (that is a habit), a one-off environment issue, or a general model limitation.

## Restructure

Only in the maintain branch, before the run is finished:

- Merge convergent habits and re-compare the merged results. Keep the id the user runs most (see the log) and delete the other with `delete-habit`.
- Normalize tags (`ts` to `typescript`, `js` to `javascript`).
- Archive stale procedures: a habit not applied in 45 days (`last_executed` in the index, or never) and created more than 30 days ago gets `archived: true`. Habits with `kind: rule` are exempt.
- Act on override patterns: scoped variants or base updates.
- Quality pass over descriptions, tags, and instructions.
- Never rename an id silently. Flag ids that break the `[a-z0-9-]` format in the summary instead.

## Summary

Write it for a person. Name each habit created or merged in one sentence each, and name every learning added. Mention restructure results in the maintain branch, proposals for new project habits, and the kinds of prompts that were skipped. Do not mention file names, counters, or timestamps. If `REMAINING` appeared, say more prompts are waiting and suggest running distill again.

Then run `bash ~/.claude/habits/bin/habit-tools.sh env-context`. If it prints `installed`, do not read or edit any plugin files. If it prints `source`, you are in a habit working tree and may append a short "Proposed source edits" section that names plugin files and describes changes in plain words, for the author to apply by hand. This is the only place file names are allowed. Do not call Read, Write, or Edit on plugin files yourself.
