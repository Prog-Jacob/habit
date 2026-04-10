---
name: edit
description: "Use when the user wants to create a new habit or update an existing one through natural language. Triggers on: saving a habit, creating a workflow, editing a prompt, defining a reusable pattern."
argument-hint: "<id> [changes or description]"
allowed-tools: Bash(bash:*)
---

# /habit:edit: Create or Update

## Existing Habit (if any)

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-habit $ARGUMENTS`

## Instructions

1. Parse `$ARGUMENTS`: first token = id (lowercase, alphanumeric + hyphens, max 40 chars), rest = changes/description.

2. The existing habit content is loaded above. If it starts with `SCOPE:<scope>`, the habit exists. If `NOT_FOUND`, it's a new habit.

| Exists? | Input? | Action                                                  |
| ------- | ------ | ------------------------------------------------------- |
| Yes     | Yes    | Apply changes to existing habit, write back             |
| Yes     | No     | Show current state, ask what to change                  |
| No      | Yes    | Create new habit from description                       |
| No      | No     | Ask what this habit should do and stop (skip steps 3-5) |

3. **Skip this step if you are only asking the user a question.** Otherwise: read `${CLAUDE_SKILL_DIR}/../habit-shared/PROCESSING.md` and apply its rules for interpretation, deduplication, and scope detection. Edit the habit in the scope where it was found. To change scope, the user must explicitly request it.

4. Write the habit by piping the complete file content (YAML frontmatter + body) to:

   ```
   bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh write-habit <scope> <id>
   ```

   This atomically writes the file, updates the index, and bumps the counter.

5. Confirm: `Created habit \`id\` [tags] description. (scope)`or`Updated habit \`id\` what changed.`
