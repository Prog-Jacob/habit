---
name: habit
description: "Use when the user mentions habits, saved prompts, reusable workflows, repeated commands, or their prompt inventory. Triggers on: browsing, searching, listing, or selecting habits."
argument-hint: "[search query]"
allowed-tools: Bash(bash:*)
---

# /habit: Entry Point & Browse

This skill is the main entry point for the Habit system. Route based on what the user is asking for:

## Triggers

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh check-triggers ${CLAUDE_SESSION_ID}`

If triggers are not `none`, add after your response: "Habit maintenance available. Run `/habit:distill` to process."

## Routing

- **Browsing/searching/listing** → handle below.
- **Viewing full details** ("show me X", "what does X do") → guide to `/habit:edit <id>` (shows full content when no changes are provided).
- **Creating or editing** → guide to `/habit:edit <id> <description>`.
- **Running a specific habit** → guide to `/habit:run <id> [override]`.
- **Watching/observing** → guide to `/habit:watch`.
- **Extracting/sweeping** → guide to `/habit:distill`.
- **Discovery** → explain the habit system briefly and suggest `/habit:edit` or `/habit:watch`.

## Global Index

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-index --scope global`

## Project Index

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-index --scope project`

## Browse & Select

1. `$ARGUMENTS` empty → list all. Non-empty → search query.

2. The indexes above are already loaded. Merge: project shadows global on same id. If both scopes have entries, show `[G]`/`[P]` indicators. Exclude archived.

3. If searching, fuzzy-match query against id, tags, description. Show only entries that match. If nothing matches, say so and suggest creating one or trying a different search.

4. Numbered list of matching entries, one line each: `N. [scope] id    tags    description`. Never mention archived entries to the user.

5. After list:

   > Pick a number or name to run, add context for an override (e.g. "1 only in auth" or "fix-types in auth"), or say "edit N" to modify.

6. **When user picks one:** guide to `/habit:run <id> [override]`.

7. Empty inventory:
   > No habits yet. Create one with `/habit:edit <name> <description>` or start watching with `/habit:watch`.
