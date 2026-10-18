<div align="center">
  <h1>Habit</h1>

  <p>A <a href="https://code.claude.com/docs/en/plugins">Claude Code</a> plugin that observes how you work and distills reusable prompts from your sessions. Habits are Markdown files with YAML frontmatter: stored locally, version-controllable, executed with semantic overrides. Relevant habits are automatically surfaced when you ask for suggestions.</p>

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

Requires [jq](https://jqlang.github.io/jq/), and either [Claude Code](https://code.claude.com/docs/en/overview) or [Cursor](https://cursor.com) 2.5+.

**Claude Code:**

```
/plugin marketplace add https://github.com/Prog-Jacob/habit.git
/plugin install habit@habit
```

**Cursor (2.5+):** install via Cursor's plugin marketplace, using the manifest in `.cursor-plugin/`. Hook commands in `hooks.cursor.json` are plugin-root-relative, so a marketplace install wires capture with no path edits. If you use both tools, install in Claude Code only: Cursor imports it.

**Development:** run `claude --plugin-dir .` from a clone.

**Upgrading to 2.2 or later:** Cursor users, run `/habit:distill project` in your active projects first. Claude Code users need no action.

---

## Usage

Habit captures every prompt you type through hooks. Use Claude Code normally, and run `/habit:distill` from time to time to turn your recent prompts into reusable habits.

The `/habit:*` forms below are Claude Code syntax. On Cursor the same skills are invoked by name or in plain language (for example, ask to run `fix-types` in the auth module, or say "distill my recent prompts").

**Create a habit from a description:**

```
/habit:edit fix-types Fix all TypeScript errors, file by file, using tsc --noEmit
```

**Run it with a scoped override:**

```
/habit fix-types only in the auth module
```

Overrides are woven into the instruction semantically ("Fix all TypeScript errors **in the auth module**"), not appended to the end. If you use the same override 3+ times, distill detects the pattern and either creates a variant (`fix-types-auth`) or updates the base habit.

**Apply relevant habits to a request:**

```
/habit:suggest refactor the auth module
```

Matches habits by tags and descriptions, merges their instructions, and addresses the request directly.

**Browse the inventory:**

```
/habit
```

Pick by number or name. Add context to narrow a run (e.g., `1 only in auth`). When the first word is a habit id, `/habit` runs that habit instead of browsing.

---

## Commands

| Command                          | What it does                                                                                                   |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `/habit [query]`                 | Browse and search the inventory. Fuzzy-matches against id, tags, and description.                              |
| `/habit <id> [override]`         | Run a habit. The override changes the instruction for this run and is logged.                                  |
| `/habit:edit <id> [description]` | Create, update, or delete a habit. Without a description, shows current content.                               |
| `/habit:suggest <request>`       | Surface relevant habits for a request, merge their instructions, and address it directly.                      |
| `/habit:distill`                 | Turn captured prompts from every project into habits. Classifies, deduplicates, writes or merges habits.       |
| `/habit:distill maintain`        | Regular sweep plus full inventory restructure: merge convergent habits, normalize tags, archive stale entries. |
| `/habit:distill undo`            | Undo the last distill run and queue its prompts again.                                                         |
| `/habit:watch`                   | Show capture status, prompts waiting for distill, and the last capture.                                        |
| `/habit:watch off [hours]`       | Pause capture on every session for 8 hours, or the given hours. `/habit:watch on` resumes it.                  |

---

## How It Works

**Hooks.** Each prompt you type is copied into a local inbox in `~/.claude/habits/inbox/`, from every project and both hosts. Short replies keep a snippet of the assistant message they answered, and common secret patterns are redacted. `SessionStart` keeps a fixed CLI path at `~/.claude/habits/bin/habit-tools.sh` up to date.

**Distill** runs in a forked subagent. It claims the inbox, groups the prompts by project, classifies each one as reusable or one-off, deduplicates against existing habits, and writes new or merged entries. `maintain` adds a full restructure pass: merging convergent habits, normalizing tags, and archiving stale entries. Every run takes a snapshot first, so `/habit:distill undo` restores the habits and queues the prompts again.

**Self-improvement.** When your prompts show friction with habit itself, distill writes a _learning_: a short standing note aimed at the skill it concerns. Each skill applies its learnings on the next run. `/habit:watch` lists them and can forget any of them. Learnings live in your data directory, so they survive updates and behave the same on Claude Code and Cursor.

**Scope.** Habits live in `~/.claude/habits/` (global) or `.claude/habits/` (project). Project habits shadow global ones with the same id.

**Storage.** Each habit is a `.md` file. Project directories hold only habit files, so they can be committed. The inbox, usage log, learnings, and snapshots stay in `~/.claude/habits/`.

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
/plugin uninstall habit@habit
```

Habit data in `~/.claude/habits/` is preserved. To delete it:

```sh
rm -rf ~/.claude/habits/
```

---

<p align="center"><sub>MIT License &copy; 2026 Ahmed Abdelaziz</sub></p>
