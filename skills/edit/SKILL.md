---
name: habit-edit
description: "Use when the user wants to create a new habit or update an existing one through natural language. Triggers on: saving a habit, creating a workflow, editing a prompt, defining a reusable pattern."
argument-hint: "<id> [changes or description]"
allowed-tools: Bash(bash:*)
disable-model-invocation: true
---

# Habit Edit: Create or Update

## Preload

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh skill-preload edit ${CLAUDE_SESSION_ID}`

Run this Setup block once and reuse the values below:

```bash
HABIT_SID_FILE=$(ls -t "$HOME/.claude/habits/sessions.d/"* 2>/dev/null | head -1)
source "${HABIT_SID_FILE:-$HOME/.claude/habits/current}" 2>/dev/null
HABIT_BIN="${HABIT_BIN:-$(command -v habit-tools.sh || echo "${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin/habit-tools.sh}")}"
[ -f "${HABIT_BIN:-}" ] || echo "HABIT_UNAVAILABLE: habit is not wired on this host."
```

If it printed `HABIT_UNAVAILABLE`, tell the user habit is not installed or its hooks are not wired, then stop. Otherwise, if no preload output appears above (hosts without harness-time injection, e.g. Cursor), run `bash "$HABIT_BIN" skill-preload edit "$HABIT_SID"` once.

The output has delimited sections: `===LEARNINGS===` (apply each note silently as standing guidance for this skill when you reach the step it bears on; never print, quote, summarize, or mention them to the user), `===TRIGGERS===` (show the message only if non-empty).

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

2. If the action is "ask", ask and stop. Otherwise apply the loaded Processing Rules. Edit in the scope where it was found. To change scope, the user must explicitly request it.
3. Write:
   ```bash
   bash "$HABIT_BIN" write-habit <scope> <id> '<frontmatter+body>'
   ```
   Confirm: "Created habit [id]. Tags: [tags]. [description]. ([scope])." or "Updated habit [id]: what changed."
