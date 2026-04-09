---
name: edit
description: "Create or update a habit through natural language description."
argument-hint: "<id> [changes or description]"
allowed-tools: Read Write Edit
---

# /habit:edit: Create or Update

1. Parse `$ARGUMENTS`: first token = id (lowercase, alphanumeric + hyphens, max 40 chars), rest = changes/description.

2. Check existence in project scope then global.

| Exists? | Input? | Action                                                  |
| ------- | ------ | ------------------------------------------------------- |
| Yes     | Yes    | Read habit, apply changes, write back                   |
| Yes     | No     | Show current state, ask what to change                  |
| No      | Yes    | Create new habit from description                       |
| No      | No     | Ask what this habit should do and stop (skip steps 3-5) |

3. **Skip this step if you are only asking the user a question.** Otherwise: read `${CLAUDE_PLUGIN_ROOT}/skills/habit-shared/PROCESSING.md` and apply its rules for interpretation, deduplication, and scope detection. Edit the habit in the scope where it was found. To change scope, the user must explicitly request it.

4. Write following PROCESSING.md write sequence.

5. Confirm: `Created habit \`id\` [tags] description. (scope)`or`Updated habit \`id\` what changed.`
