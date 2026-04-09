---
name: habit
description: "The Habit system, a living inventory of reusable prompts and workflows. Use this skill whenever the user mentions habits, saved prompts, reusable workflows, repeated commands, capturing patterns, watching sessions, extracting patterns, distilling conversations, or anything about their prompt inventory. This is the entry point for all habit-related requests: browsing, creating, running, watching, and distilling."
argument-hint: "[search query]"
---

# /habit: Entry Point & Browse

This skill is the main entry point for the Habit system. Route based on what the user is asking for:

## Routing

- **Browsing/searching/listing** ("show my habits", "what do I have saved", "find my fix-types habit") → handle below.
- **Creating or editing** ("save this as a habit", "create a habit for X") → guide to `/habit-edit <id> <description>`.
- **Running a specific habit** ("run fix-types", "do the lint thing") → guide to `/habit-run <id> [override]`.
- **Watching/observing** ("watch my session", "capture patterns automatically") → guide to `/habit-watch`.
- **Extracting/sweeping** ("extract patterns from this session", "distill my conversation") → guide to `/habit-distill`.
- **Discovery** ("I keep repeating the same commands", "is there a way to save workflows?") → explain the habit system briefly and suggest getting started with `/habit-edit` or `/habit-watch`.

## Browse & Select

1. `$ARGUMENTS` empty → list all. Non-empty → search query.

2. Load `_index.json` from project (`.claude/habits/`) then global (`~/.claude/habits/`). Merge: project shadows global on same id. Missing index but `.md` files exist? Rebuild from frontmatter (tell the user "Rebuilt your habit list", don't mention file names or implementation details).

3. If searching, fuzzy-match query against id, tags, description.

4. Numbered list, one line each. Show `[G]`/`[P]` only when both scopes have entries (G = global, P = project). Exclude archived.

5. After list:

   > Pick a number or name to run, add context for an override (e.g. "1 only in auth" or "fix-types in auth"), or say "edit N" to modify.

6. **When user picks one:** read `~/.claude/skills/habit-run/SKILL.md` and follow its instructions to execute the selected habit.

7. Empty inventory:
   > No habits yet. Create one with `/habit-edit <name> <description>` or start watching with `/habit-watch`.

Only read index for listing. Load full `.md` only when user selects one.
