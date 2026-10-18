---
name: habit-edit
description: "Use when the user wants to create, update, or delete a habit through natural language. Triggers on: saving a habit, creating a workflow, editing a prompt, defining a reusable pattern, removing a habit."
argument-hint: "<id> [changes or description]"
allowed-tools: Bash(bash:*)
disable-model-invocation: true
---

# Habit Edit: Create, Update, or Delete

## Preload

Run this once before anything else:

```bash
bash ~/.claude/habits/bin/habit-tools.sh preload edit
```

If the command is missing, tell the user habit's hooks have not run yet and to start a new session, then stop.

The output has two sections: `===LEARNINGS===` (standing guidance for this skill: apply each note silently when you reach the step it bears on; never print, quote, summarize, or mention them) and `===PROCESSING===` (the processing rules).

## Load the habit

The first token of the message is the id (lowercase letters, digits, and hyphens, at most 40 characters). The rest is the change or description. Load it:

```bash
bash ~/.claude/habits/bin/habit-tools.sh read-habit <id>
```

## Instructions

Output: the confirmation message or the question to the user.

1. Output starting with `SCOPE:<scope>` means the habit exists. `NOT_FOUND` means it is new.

| Exists? | Input?          | Action                                      |
| ------- | --------------- | ------------------------------------------- |
| Yes     | Asks to delete  | Delete it                                   |
| Yes     | Yes             | Apply changes to existing habit, write back |
| Yes     | No              | Show current state, ask what to change      |
| No      | Yes             | Create new habit from description           |
| No      | No              | Ask what this habit should do and stop      |

2. If the action is "ask", ask and stop. Otherwise apply the processing rules. Edit in the scope where the habit was found. Change scope only when the user asks: write it in the new scope, then delete the old copy.
3. Keep the id. Users run habits by id, so never rename one silently. Rename only when the user asks, by writing the new id and deleting the old one, and say so.
4. On an update, keep `created` and any `last_executed` line exactly as they are, and set `updated` to now. Never add `last_executed`.
5. Write:
   ```bash
   bash ~/.claude/habits/bin/habit-tools.sh write-habit <scope> <id> '<frontmatter+body>'
   ```
   Confirm: "Created habit [id]. Tags: [tags]. [description]. ([scope])." or "Updated habit [id]: what changed."
6. Delete:
   ```bash
   bash ~/.claude/habits/bin/habit-tools.sh delete-habit <scope> <id>
   ```
   Confirm: "Deleted habit [id] ([scope])."
