<div align="center">
  <h1>Habit</h1>

  <p>A plugin for <a href="https://code.claude.com/docs/en/plugins">Claude Code</a> and <a href="https://cursor.com">Cursor</a> that learns how you like to work and applies it for you.</p>

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
<a href="#privacy">Privacy</a>
<span>&nbsp;&middot;&nbsp;</span>
<a href="https://github.com/Prog-Jacob/habit/issues">Report a Bug</a>

<br /><br />

</div>

Habit keeps a local copy of the prompts you type. When you ask, it distills them into _habits_: short standing rules ("never use em dashes") and longer procedures ("review a PR this way"). Rules load into every new session automatically, so you stop repeating yourself. Procedures load when a request needs them. Habits are plain Markdown files that you can read, edit, and commit, and they work the same on both hosts.

## Example

**Before.** You correct the same thing in session after session:

```
> no em dashes please
> again, no em dashes, use a period or a colon
> rewrite that without the dashes
```

**Distill.** You run `/habit:distill`. It sees the repeated correction and writes one rule:

```markdown
---
id: no-dashes
description: Use periods or colons instead of dashes in prose.
kind: rule
---

Never join clauses with an em dash, en dash, or double hyphen. Use a period, comma, colon, or parentheses.
```

**After.** Every new session starts with that rule already in context. You type nothing extra.

---

## Install

Requires [jq](https://jqlang.github.io/jq/), and [Claude Code](https://code.claude.com/docs/en/overview) or [Cursor](https://cursor.com) 2.5 or later. Install **one copy per machine**.

| You use | Install |
| --- | --- |
| Claude Code | `/plugin marketplace add https://github.com/Prog-Jacob/habit.git`, then `/plugin install habit@habit` |
| Claude Code and Cursor | Install in Claude Code only. Cursor imports Claude Code plugins, so a second install would load habit twice. |
| Cursor only | Install habit from Cursor's plugin marketplace. |

Then enable auto-update for the habit marketplace (in Claude Code, open `/plugin` and choose the marketplace). Neither host auto-updates third-party marketplaces by default.

**Cursor:** a rule shipped with the plugin runs `bash ~/.claude/habits/bin/habit-tools.sh preload rules` at the start of each conversation. Add that command to Cursor's command allowlist so it runs without a prompt.

**Development:** run `claude --plugin-dir .` from a clone.

### Upgrading from 2.x

- **Cursor users on 2.1 or earlier:** before you upgrade, run `/habit:distill project` in each active project. Later versions read only their own inbox, so Cursor sessions that were never distilled are not imported.
- **Claude Code users:** no action. The first session after an upgrade from 2.1 or earlier backfills the last 30 days of typed prompts from Claude Code's history.

Your habits and learnings carry over. The old `settings.local.json` files stay untouched; `/habit:watch` tells you when they are safe to delete.

---

## Usage

The `/habit:*` forms are Claude Code syntax. On Cursor, call the same skills by name or in plain words (for example, "distill my recent prompts").

**Rules load by themselves.** Each new session gets your active rules, a one-line index of your procedures, and a reminder when distill is due. You do not type anything.

**Apply procedures to a request:**

```
/habit:suggest review this PR
```

It picks the procedures that fit, merges them into one instruction, and does the work. Rules already in the session are skipped.

**Run one habit, with an override:**

```
/habit fix-types only in the auth module
```

The override is woven into the instruction ("fix all TypeScript errors **in the auth module**"), not appended. When you give the same override three or more times, distill turns it into a variant or updates the base habit. `/habit` with no id browses the inventory.

**Distill your prompts:**

```
/habit:distill            # turn captured prompts into habits
/habit:distill maintain   # also classify rules and procedures, tighten rules, clean up
/habit:distill undo       # restore everything the last run changed; again to step further back
```

**Watch habit itself:**

```
/habit:watch              # health report
/habit:watch off 4        # pause capture for 4 hours (8 by default); /habit:watch on resumes
/habit:watch snooze 3     # no distill reminder for 3 days (7 by default)
/habit:watch forget 2     # remove learning number 2
```

---

## Commands

| Command | What it does |
| --- | --- |
| `/habit [query]` | Browse and search the inventory by id, tags, and description. |
| `/habit <id> [override]` | Run one habit. The override changes this run only and is logged. |
| `/habit:suggest <request>` | Apply the relevant procedures (and any rules not loaded) to a request. |
| `/habit:edit <id> [change]` | Create, update, or delete a habit in plain words. You can also set its kind. |
| `/habit:distill` | Turn captured prompts from every project into new or merged habits. |
| `/habit:distill maintain` | Distill, then classify every habit as a rule or a procedure, rewrite rules to be terse, archive habits your `CLAUDE.md`, `AGENTS.md`, or memory already states, merge duplicates, and archive stale procedures. |
| `/habit:distill undo` | Undo the last distill run and queue its prompts again. Each further undo steps one run back. |
| `/habit:watch [status]` | Show installed copies, capture per host, the backlog, the last distill, habit counts, the rule budget, learnings, and integrity checks. |
| `/habit:watch off [hours]` / `on` | Pause capture everywhere for 8 hours or the given hours, or resume it. |
| `/habit:watch snooze [days]` | Silence the distill reminder for 7 days or the given days. |
| `/habit:watch forget <n>` | Remove a learning by its number. |

---

## How It Works

**Capture.** A prompt hook copies each prompt you type into a local inbox, from every project and both hosts. Slash commands are stripped and prompts under three words are dropped. A short reply also keeps the last 300 characters of the assistant message it answered, so "yes, and no hyphens either" still makes sense later.

**Inbox.** One file per session in `~/.claude/habits/inbox/`. Distill claims the files by moving them, so new prompts never collide with a running distill.

**Distill.** You start it; it never runs on its own. It groups the prompts by project, keeps the ones that describe how you work, skips anything your existing habits or your `CLAUDE.md`, `AGENTS.md`, or memory already cover, and writes new or merged habits. Every run takes a snapshot first, so `/habit:distill undo` restores the habits and learnings and queues the prompts again.

**Rules injection.** A habit has `kind: rule` or `kind: procedure` (missing means procedure). A rule body is at most 600 characters, about 300 after `maintain`. At session start, habit loads your active rules: global rules first, then the current project's rules, which win a conflict. The block stays under 8,000 characters. Project rules get the space first, and any rule that does not fit is listed by id so it can still be loaded on demand. Claude Code gets the block from the session start hook. Cursor gets it through the plugin's always-on rule.

**Notices.** When at least 30 prompts wait and the oldest is a week old (or 300 wait), a new session shows one reminder a day to run `/habit:distill`. Cursor shows it before compacting the context, and both hosts see it in the rules block.

**Learnings.** When your prompts show friction with habit itself, distill writes a learning: a short note aimed at the skill concerned, which that skill applies on its next run. `/habit:watch` lists them and can forget any of them.

**Scope.** Habits live in `~/.claude/habits/` (global) or `<repo>/.claude/habits/` (project). A project habit replaces a global one with the same id.

---

## Privacy

- The inbox stays on your machine. Habit itself makes no network calls.
- Inbox files are created with mode 600, readable only by you.
- Common secrets are replaced with `[redacted]` before anything is written: API keys (`sk-`, `ghp_`, `github_pat_`, `xox?-`, `AKIA`), private key blocks, and `password=`, `secret=`, `token=` values.
- `/habit:watch off` pauses capture on every session until it expires.
- Prompts from finished distill runs are deleted after 90 days.

---

## Platforms

macOS and Linux, including root in containers. Windows through WSL only. Habit needs bash 3.2 or later, jq 1.6 or later, and standard tools (awk, sed, tar). CI runs the suite on macOS (bash 3.2 with jq 1.7 and the latest jq), Ubuntu (jq 1.7), and Debian 12 (jq 1.6) as a normal user and as root.

---

## Storage

```
~/.claude/habits/
  *.md                      global habits
  learnings.jsonl           learnings (append only)
  log/YYYY-MM.jsonl         usage log, kept 6 months
  inbox/<host>-<sid>.jsonl  captured prompts; .claimed/ and .done/ hold distill runs
  snapshots/<run>.tar.gz    the last 10 snapshots, for undo
  bin/habit-tools.sh        fixed CLI path, kept pointing at the newest install
  paused, nudge.next        capture pause and reminder times
  .v3                       data version marker
<repo>/.claude/habits/*.md  project habits, safe to commit
```

A habit file:

```markdown
---
id: fix-types
tags: [typescript]
description: Fix TypeScript errors in the specified scope.
scope: global
created: 2026-04-09T14:30:00Z
updated: 2026-04-09T14:30:00Z
archived: false
kind: procedure
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

Your data in `~/.claude/habits/` is kept. To delete it:

```sh
rm -rf ~/.claude/habits/
```

---

<p align="center"><sub>MIT License &copy; 2026 Ahmed Abdelaziz</sub></p>
