# Habit: Intelligent Prompt Inventory

Habit observes how you work, captures your repeated patterns into structured prompts, and evolves the collection through a feedback loop driven by actual usage.

## Install

```
/plugin marketplace add https://github.com/Prog-Jacob/habit.git
/plugin install habit@habit
```

Storage is created automatically on first use.

## Commands

| Command                          | Purpose                                     |
| -------------------------------- | ------------------------------------------- |
| `/habit:habit`                   | Browse, search, and select habits           |
| `/habit:run <id> [override]`     | Execute a habit, optionally with context    |
| `/habit:edit <id> [description]` | Create or update a habit                    |
| `/habit:watch`                   | Start observing the session for patterns    |
| `/habit:watch off`               | Stop observing, process captured patterns   |
| `/habit:distill`                 | Sweep current session for reusable patterns |
| `/habit:distill deep`            | Full inventory restructure and cleanup      |

## How It Works

**Capture.** Create habits explicitly with `/habit:edit`, or let the system find them with `/habit:watch` and `/habit:distill`.

**Execute.** Run habits with `/habit:run`. Add overrides like "only in auth module" and they get woven into the instruction semantically, not appended blindly.

**Evolve.** Every execution with an override is a signal. When the system detects repeated overrides (3+), it creates new habit variants or updates the base habit automatically during `/habit:distill deep`.

## Scope

Habits can be **global** (`~/.claude/habits/`) or **project-scoped** (`.claude/habits/`). Auto-detected based on whether the instruction references project-specific paths. Project habits shadow global ones with the same name.

## Storage

All human-readable and portable. Markdown habits with YAML frontmatter, JSON index, JSONL execution log.

## Uninstall

Remove through Claude Code's plugin manager. Habit data at `~/.claude/habits/` is preserved. To remove data too: `rm -rf ~/.claude/habits/`
