# Habit

A Claude Code plugin that turns the way you work into reusable prompts. It watches your sessions, extracts patterns, and builds an inventory that improves over time.

## Install

```
/plugin marketplace add https://github.com/Prog-Jacob/habit.git
```

Then:

```
/plugin install habit@habit
```

## Quick Start

Habit watches every session automatically. Use Claude Code normally. After enough prompts, it suggests running `/habit:distill` to extract reusable patterns.

Create a habit directly:

```
/habit:edit fix-types Fix all TypeScript errors, file by file, using tsc --noEmit
```

Run one with an override:

```
/habit:run fix-types only in the auth module
```

The override is woven into the instruction semantically, not appended to the end.

Browse the full inventory:

```
/habit
```

## Commands

| Command                          | What it does                                                                                                                                          |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/habit [query]`                 | Browse and search the inventory. Pick by number or name to run.                                                                                       |
| `/habit:run <id> [override]`     | Execute a habit. The override narrows or modifies the instruction for this run.                                                                       |
| `/habit:edit <id> [description]` | Create or update a habit. Without a description, shows current content.                                                                               |
| `/habit:distill`                 | Sweep the current session and any unprocessed prior sessions for reusable patterns. Deduplicates, merges, and skips one-off messages.                 |
| `/habit:distill deep`            | Full inventory restructure on top of a regular distill: merge overlapping habits, normalize tags, archive stale entries, promote recurring overrides. |
| `/habit:watch`                   | Check observation status and prompt count for the current session.                                                                                    |
| `/habit:watch off`               | Pause observation for this session. Resumes automatically next session.                                                                               |

## How It Works

1. **Session hooks** track every session automatically. On start, a session is registered. On each prompt, a counter increments. On end, a breadcrumb is saved for later processing.
2. **Distill** reads the current session transcript plus any saved breadcrumbs from prior sessions. It classifies prompts as reusable or one-off, deduplicates against existing habits, and writes new or merged entries.
3. **Overrides** are logged every time you run a habit with extra context. When `/habit:distill deep` detects 3+ similar overrides on the same habit, it either creates a scoped variant (e.g., `fix-types-auth`) or updates the base habit.
4. **Triggers** surface maintenance suggestions at the right time. After enough prompts or accumulated changes, skill invocations will note that distill is available.

## Scope

Habits live in one of two directories:

- **Global**: `~/.claude/habits/`. Default for generic instructions.
- **Project**: `.claude/habits/`. Used when the instruction references project paths or config.

Project habits shadow global ones with the same id in the merged index.

## Storage

Each habit is a Markdown file with YAML frontmatter. Session and index state is tracked in `settings.local.json` per scope. Everything is human-readable and version-controllable.

## Uninstall

Remove through Claude Code's plugin manager. Habit data in `~/.claude/habits/` is preserved. To delete it: `rm -rf ~/.claude/habits/`
