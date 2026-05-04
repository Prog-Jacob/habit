<div align="center">
  <h1>Habit</h1>

  <p>A <a href="https://code.claude.com/docs/en/plugins">Claude Code</a> plugin that observes how you work and distills reusable prompts from your sessions. Habits are Markdown files with YAML frontmatter: stored locally, version-controllable, executed with semantic overrides.</p>

  <p>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/Prog-Jacob/habit?style=for-the-badge&colorA=1e1e2e&colorB=cba6f7" alt="MIT License" /></a>
  </p>

<a href="#install">Install</a>
<span>&nbsp;&middot;&nbsp;</span>
<a href="#usage">Usage</a>
<span>&nbsp;&middot;&nbsp;</span>
<a href="#commands">Commands</a>
<span>&nbsp;&middot;&nbsp;</span>
<a href="#how-it-works">How It Works</a>
<span>&nbsp;&middot;&nbsp;</span>
<a href="https://github.com/Prog-Jacob/habit/issues">Report a Bug</a>

<br /><br />

</div>

## Install

Requires [Claude Code](https://code.claude.com/docs/en/overview) and [jq](https://jqlang.github.io/jq/).

```
/plugin marketplace add Prog-Jacob/habit
/plugin install habit@prog-jacob-habit
```

---

## Usage

Habit observes every session through hooks. Use Claude Code normally. After enough prompts, skills suggest running `/habit:distill` to extract reusable patterns.

**Create a habit from a description:**

```
/habit:edit fix-types Fix all TypeScript errors, file by file, using tsc --noEmit
```

**Run it with a scoped override:**

```
/habit:run fix-types only in the auth module
```

Overrides are woven into the instruction semantically ("Fix all TypeScript errors **in the auth module**"), not appended to the end. If you use the same override 3+ times, distill detects the pattern and either creates a variant (`fix-types-auth`) or updates the base habit.

**Browse the inventory:**

```
/habit
```

Pick by number or name. Add context to narrow a run (e.g., `1 only in auth`).

---

## Commands

| Command                          | What it does                                                                                                   |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `/habit [query]`                 | Browse and search the inventory. Fuzzy-matches against id, tags, and description.                              |
| `/habit:run <id> [override]`     | Execute a habit. Override modifies the instruction for this run and is logged.                                 |
| `/habit:edit <id> [description]` | Create or update a habit. Without a description, shows current content.                                        |
| `/habit:distill`                 | Sweep the current session and any pending prior sessions. Classifies, deduplicates, writes or merges habits.   |
| `/habit:distill maintain`        | Regular sweep plus full inventory restructure: merge convergent habits, normalize tags, archive stale entries. |
| `/habit:distill project`         | Scan all project sessions and restructure the full inventory.                                                  |
| `/habit:watch`                   | Check observation status and prompt count for the current session.                                             |
| `/habit:watch off`               | Pause observation. Resumes automatically next session.                                                         |

---

## How It Works

**Hooks** fire on every session. `SessionStart` registers the session. `UserPromptSubmit` increments a prompt counter (skips prompts under 5 words) and records the transcript path. `SessionEnd` saves a breadcrumb for later distill if any prompts were captured.

**Distill** runs in a forked subagent. It preloads the current transcript, the merged habit index, pending sessions, execution log, and metadata. It classifies each prompt as reusable or one-off, deduplicates against existing habits, and writes new or merged entries. `maintain` adds a restructure pass. `project` scans all `.jsonl` session files for the current working directory.

**Scope.** Habits live in `~/.claude/habits/` (global) or `.claude/habits/` (project). Project habits shadow global ones with the same id.

**Storage.** Each habit is a `.md` file. Session state and indexes live in `settings.local.json` per scope.

```markdown
---
id: fix-types
tags: [typescript, linting]
description: Fix TypeScript type errors in the specified scope.
scope: global
created: 2026-04-09T14:30:00Z
updated: 2026-04-09T14:30:00Z
archived: false
last_executed: 2026-04-11T18:14:28Z
---

## Instruction

Run `tsc --noEmit` and fix every reported error, file by file.
Prefer narrowing types over adding `as` casts.
```

---

## Uninstall

```
/plugin uninstall habit@prog-jacob-habit
```

Habit data in `~/.claude/habits/` is preserved. To delete it:

```sh
rm -rf ~/.claude/habits/
```

---

<p align="center"><sub>MIT License &copy; 2026 Ahmed Abdelaziz</sub></p>
