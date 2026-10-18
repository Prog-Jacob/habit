<div align="center">
  <h1>Habit</h1>

  <p><strong>Stop repeating yourself to your coding agent.</strong><br />
  Habit learns how you work from the prompts you type, and brings it to every new session.<br />
  For <a href="https://code.claude.com/docs/en/plugins">Claude Code</a> and <a href="https://cursor.com">Cursor</a>.</p>

  <p>
    <a href="https://github.com/Prog-Jacob/habit/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/Prog-Jacob/habit/ci.yml?branch=main&style=for-the-badge&labelColor=1e1e2e&color=a6e3a1&label=CI" alt="CI" /></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-cba6f7?style=for-the-badge&labelColor=1e1e2e" alt="MIT License" /></a>
  </p>

<a href="#install">Install</a>
<span>&nbsp;&middot;&nbsp;</span>
<a href="#commands">Commands</a>
<span>&nbsp;&middot;&nbsp;</span>
<a href="#how-it-works">How It Works</a>
<span>&nbsp;&middot;&nbsp;</span>
<a href="#privacy">Privacy</a>
<span>&nbsp;&middot;&nbsp;</span>
<a href="#development">Development</a>
<span>&nbsp;&middot;&nbsp;</span>
<a href="https://github.com/Prog-Jacob/habit/issues">Report a Bug</a>

</div>

---

Habit saves the prompts you type. When you run `/habit:distill`, it turns the patterns in them into **habits**:

- A **rule** is a short preference, such as "run the tests before you say done". Every new session starts with your rules loaded.
- A **procedure** is a workflow, such as how you review a PR. It loads when a request needs it.

Habits are plain Markdown files. You can read them, edit them, and commit them with your code.

```mermaid
flowchart LR
  A["Your prompts"] -->|saved| B[("Local inbox")]
  B -->|"/habit:distill"| C["Rules and procedures"]
  C -->|"loaded"| D["Every new session"]
```

## A week with Habit

**During the week**, across three repos, you type things like:

```
> don't add comments that just repeat the code
> run the related tests before you tell me it's done
> review this PR: read the whole diff, check edge cases, then naming and style
> again, no comments that repeat the code
```

**On Friday**, you run `/habit:distill`. It reports something like:

```
Created 2 rules and 1 procedure:
  no-obvious-comments  (rule)       Write no comment that only repeats the code.
  tests-before-done    (rule)       Run the related tests before you call a change done.
  pr-review            (procedure)  Review a PR: the full diff, then edge cases, then naming and style.
Skipped 1 pattern that your CLAUDE.md already states.
```

**From Monday**, every new session starts with both rules. You stop typing them. To review a PR your way, run the procedure, and add an override if you want one:

```
/habit pr-review focus on the auth changes
```

## Install

Install **one copy per machine**.

| You use                | Do this                                                                                                    |
| ---------------------- | ---------------------------------------------------------------------------------------------------------- |
| Claude Code            | Run `/plugin marketplace add https://github.com/Prog-Jacob/habit.git`, then `/plugin install habit@habit`. |
| Claude Code and Cursor | Install in Claude Code only. Cursor imports Claude Code plugins.                                           |
| Cursor only            | Install Habit from Cursor's plugin marketplace.                                                            |

Then:

1. Turn on auto-update for the habit marketplace (in Claude Code, open `/plugin`). Neither host does this for you.
2. **Cursor only:** add `bash ~/.claude/habits/bin/habit-tools.sh preload rules` to the command allowlist. Habit runs it at the start of each conversation to load your rules.
3. Start a new session. Habit saves prompts from then on.

Habit needs [jq](https://jqlang.github.io/jq/) 1.6 or later, and Claude Code or Cursor 2.5 or later.

<details>
<summary><strong>Upgrading from 2.x</strong></summary>

<br />

- **Claude Code:** no action. The first session after the upgrade imports your typed prompts from the last 30 days.
- **Cursor:** 3.0 does not import Cursor sessions that you never distilled under 2.x. If you have not upgraded yet, run `/habit:distill project` in each active project first.

Your habits and learnings carry over. Habit does not change the old `settings.local.json` files, and `/habit:watch` tells you when you can delete them.

</details>

## Commands

| Command                      | What it does                                                          |
| ---------------------------- | --------------------------------------------------------------------- |
| `/habit:distill`             | Turn the saved prompts into new or merged habits.                     |
| `/habit:distill maintain`    | Distill, then tidy all habits: classify, tighten, merge, and archive. |
| `/habit:distill undo`        | Undo the last distill. Run it again to go back one more run.          |
| `/habit:suggest <request>`   | Do the request with the procedures that fit it.                       |
| `/habit <id> [override]`     | Run one habit. The override applies to this run only.                 |
| `/habit [search]`            | List or search your habits.                                           |
| `/habit:edit <id> [change]`  | Create, change, or delete a habit in plain words.                     |
| `/habit:watch`               | Show the health report.                                               |
| `/habit:watch off [hours]`   | Pause saving prompts (8 hours by default). `on` resumes it.           |
| `/habit:watch snooze [days]` | Stop the distill reminder (7 days by default).                        |
| `/habit:watch forget <n>`    | Remove a learning by its number.                                      |

On Cursor, ask in plain words ("distill my recent prompts") or use the skill names: `habit`, `habit-distill`, `habit-suggest`, `habit-edit`, `habit-watch`.

## How it works

**Capture.** A prompt hook saves each prompt you type to a local inbox, from every project and both hosts. It removes leading slash commands and drops prompts of fewer than three words. A short reply keeps the end of the message it answers, so "yes, and no hyphens either" still makes sense later.

**Distill.** It runs only when you start it. It keeps the prompts that show how you work and skips what your habits, `CLAUDE.md`, `AGENTS.md`, or memory already say. Then it writes new habits or merges them into existing ones. Each run takes a snapshot first, so you can undo it.

**Rules.** Each new session loads your active rules: global rules first, then the current project's rules, which win a conflict. A rule is at most 600 characters, and all rules together stay within 8,000. If a rule does not fit, the session gets its id, so it can still load when needed.

**Reminders.** Distill is due when at least 30 prompts wait and the oldest is a week old, or when at least 300 wait. A new session then reminds you, at most once a day. Cursor shows the reminder before it compacts the context.

**Learnings.** When you complain about Habit itself, distill writes a note for the skill concerned. That skill follows the note from its next run. `/habit:watch` lists the notes.

**Scope.** Global habits are in `~/.claude/habits/`. Project habits are in `<repo>/.claude/habits/`, and they replace a global habit with the same id.

## Privacy

- Your prompts stay on your machine. Habit makes no network calls.
- Inbox files have mode 600, so only you can read them.
- Habit replaces common secrets with `[redacted]` before it saves a prompt: API keys (`sk-`, `ghp_`, `github_pat_`, `xox?-`, `AKIA`), private key blocks, and `password=`, `secret=`, and `token=` values.
- `/habit:watch off` pauses saving in all sessions.
- Habit deletes distilled prompts after 90 days.

## Platforms

macOS and Linux, also as root in containers. Windows through WSL only. Habit needs bash 3.2 or later, jq 1.6 or later, awk, sed, and tar.

CI tests macOS with bash 3.2 (Homebrew jq and the macOS jq), Ubuntu, and Debian 12 with jq 1.6, as a normal user and as root.

<details>
<summary><strong>Files</strong></summary>

<br />

```
~/.claude/habits/
  *.md                      global habits
  learnings.jsonl           learnings
  log/YYYY-MM.jsonl         usage log, kept 6 months
  inbox/                    saved prompts, one file per session
  snapshots/                the last 10 distill snapshots, for undo
  bin/habit-tools.sh        the CLI path that skills call
  paused, nudge.next        pause and reminder times
<repo>/.claude/habits/*.md  project habits, safe to commit
```

A rule:

```markdown
---
id: tests-before-done
tags: [testing]
description: Run the related tests before you call a change done.
kind: rule
---

Before you call a change done, run the tests that cover it and report the result.
```

A procedure:

```markdown
---
id: pr-review
tags: [git, review]
description: Review a PR for correctness first, then naming and style.
kind: procedure
---

## Instruction

1. Read the full diff.
2. Check edge cases and error paths in each changed function.
3. Check naming and style last.
```

</details>

## Uninstall

In Claude Code, run `/plugin uninstall habit@habit`. In Cursor, remove Habit in the plugin settings.

Your habits stay in `~/.claude/habits/`. To delete them too, run `rm -rf ~/.claude/habits/`.

## Development

```sh
git clone https://github.com/Prog-Jacob/habit.git && cd habit
claude --plugin-dir .   # use this checkout as the plugin
make check              # ShellCheck, then the bats suite
```

`make check` needs [ShellCheck](https://www.shellcheck.net/), [bats-core](https://github.com/bats-core/bats-core) 1.5 or later, and jq.

The skills do the thinking. The CLI only reads and writes files, and it checks each habit before it saves it.

| Path              | Contents                                                          |
| ----------------- | ----------------------------------------------------------------- |
| `skills/`         | The five skills, and the rules and command reference they share.  |
| `bin/`            | The CLI that skills and hooks call, with one library per concern. |
| `hooks/`          | Hook configs for both hosts, and the script they run.             |
| `rules/habit.mdc` | The Cursor rule that loads your rules.                            |
| `test/`           | The bats suite.                                                   |

<p align="center"><sub>MIT License &copy; 2026 Ahmed Abdelaziz</sub></p>
