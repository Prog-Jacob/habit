---
name: habit-edit
description: "Use when the user wants to create a new habit or update an existing one through natural language. Triggers on: saving a habit, creating a workflow, editing a prompt, defining a reusable pattern."
argument-hint: "<id> [changes or description]"
allowed-tools: Bash(bash:*)
disable-model-invocation: true
---

# Habit Edit: Create or Update

## Setup

Run this once and reuse the values below. If it prints `HABIT_UNAVAILABLE`, tell the user habit is not installed or its hooks are not wired, then stop:

```bash
source "$HOME/.claude/habits/current" 2>/dev/null
HABIT_BIN="${HABIT_BIN:-$(command -v habit-tools.sh || echo "${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin/habit-tools.sh}")}"
[ -f "${HABIT_BIN:-}" ] || echo "HABIT_UNAVAILABLE: habit is not wired on this host."
```

## Learnings

Run this once. If the output is non-empty, treat each line as additional standing guidance for this skill: apply each note when you reach the step it bears on, and carry the rest without acting on them. Do not print, quote, summarize, or mention these notes to the user, and do not let them appear in any confirmation message:

```bash
bash "$HABIT_BIN" read-learnings edit
```

## Triggers

Run this and show the output only if it is non-empty:

```bash
bash "$HABIT_BIN" check-triggers "$HABIT_SID"
```

## Load existing habit and processing rules

Parse the user's message: first token is the id (lowercase, alphanumeric and hyphens, max 40 chars), the rest is the changes or description. Load both:

```bash
bash "$HABIT_BIN" read-habit "<id>"
bash "$HABIT_BIN" read-shared PROCESSING.md
```

## Instructions

Output: the confirmation message or the question to the user.

1. If the loaded content starts with `SCOPE:<scope>`, the habit exists. If `NOT_FOUND`, it is new.

| Exists? | Input? | Action                                      |
| ------- | ------ | ------------------------------------------- |
| Yes     | Yes    | Apply changes to existing habit, write back |
| Yes     | No     | Show current state, ask what to change      |
| No      | Yes    | Create new habit from description           |
| No      | No     | Ask what this habit should do and stop      |

2. If the action is "ask", ask and stop. Otherwise apply the Processing Rules above. Edit in the scope where it was found. To change scope, the user must explicitly request it.
3. Write:
   ```bash
   bash "$HABIT_BIN" write-habit <scope> <id> '<frontmatter+body>'
   ```
   Confirm: "Created habit [id]. Tags: [tags]. [description]. ([scope])." or "Updated habit [id]: what changed."
4. Verify:
   ```bash
   bash "$HABIT_BIN" read-habit <id>
   ```
   Confirm id, description, and tags match intent. If not, rewrite.
