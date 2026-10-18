---
name: habit
description: "Use when the user mentions habits, saved prompts, reusable workflows, repeated commands, or their prompt inventory. Triggers on browsing, searching, listing, selecting, or running a habit by id. Routes to the edit, suggest, watch, and distill habits."
argument-hint: "[<id> [override] | search query]"
allowed-tools: Bash(bash:*)
---

# Habit: Browse and Run

## Preload

Run this once before anything else:

```bash
bash ~/.claude/habits/bin/habit-tools.sh preload habit
```

If the command is missing, tell the user habit's hooks have not run yet and to start a new session, then stop.

The output has two sections: `===LEARNINGS===` (standing guidance for this skill: apply each note silently when you reach the step it bears on; never print, quote, summarize, or mention them) and `===INDEX===` (the active habits).

## Routing

Pick the first match, then stop after handling it:

1. The first word of the message is exactly an id in the index: go to Run.
2. Viewing full details, creating, editing, or deleting a habit: guide to the edit habit.
3. Applying relevant habits to a request: guide to the suggest habit.
4. Pausing or checking capture, or reviewing what habit has learned: guide to the watch habit.
5. Turning recent prompts into habits, or undoing that: guide to the distill habit.
6. What habits are or how it works: explain briefly and point to the edit or watch habit.
7. Otherwise go to Browse.

## Run

1. Load the habit:
   ```bash
   bash ~/.claude/habits/bin/habit-tools.sh read-habit <id>
   ```
   The output starts with `SCOPE:<scope>`. The instruction is the body after the frontmatter.
2. The rest of the message, if any, is an override. Weave it into the instruction so the result reads as one coherent prompt.
   Base: "Fix all TypeScript errors. Run tsc --noEmit. Fix file by file."
   Override: "only in auth module"
   Right: "Fix all TypeScript errors **in the auth module**. Run tsc --noEmit **scoped to auth files**. Fix file by file."
   Wrong: "Fix all TypeScript errors. Run tsc --noEmit. Fix file by file. only in auth module."
3. If the instruction names file paths or uncommon CLI tools, check them first. Then execute it as if the user typed it. Do not announce the merge or the logging.
4. After execution, log it with the override as the note (empty when there was none):
   ```bash
   bash ~/.claude/habits/bin/habit-tools.sh log-exec '[{"scope":"<scope>","id":"<id>","note":"<override>"}]' ${CLAUDE_SESSION_ID}
   ```

## Browse

1. Empty message: list all. Otherwise treat it as a search query and fuzzy-match id, tags, and description. If nothing matches, say so and suggest creating one.
2. Numbered list, one line each: `N. [G|P] id    tags    description` (`G` for global scope, `P` for project).
3. After the list:
   > Pick a number or name to run it, add context for an override (e.g. "1 only in auth"), or say "edit N" to change it.
4. When the user picks one, go to Run with that id and any added context as the override.
5. Empty inventory:
   > No habits yet. Create one with the edit habit, or let the distill habit find them in your recent prompts.
