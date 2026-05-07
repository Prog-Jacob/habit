---
name: suggest
description: "Use when the user wants to apply relevant habits to their request without naming them individually. Triggers on: suggest habits, apply habits, help with [task] using habits."
argument-hint: "<request>"
allowed-tools: Bash(bash:*)
---

# /habit:suggest: Surface & Apply

## Triggers

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh check-triggers ${CLAUDE_SESSION_ID}`

## Index (active)

!`bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-index merged active`

## Instructions

1. Parse `$ARGUMENTS` as the user's request. No arguments: `Usage: /habit:suggest <request>`. Point to `/habit`.

2. Score each non-archived habit in the index above for relevance to the request. Use id, tags, and description. Select habits that would meaningfully improve how the request is addressed. Skip habits that are only tangentially related.

3. If no habits are relevant, address the request directly without further ceremony.

4. Load all relevant habits in one call: `bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh read-habit <id1> <id2> ...`. Output is delimited by `---HABIT:<id>---` lines. Each section starts with `SCOPE:<scope>`. Note the scope per habit for logging. Extract the instruction body after the YAML frontmatter.

5. Merge the loaded instructions into a single directive for the request. Apply all habit instructions to the request. Where two instructions conflict, the more narrowly scoped one wins. Do not execute habits sequentially; synthesize one coherent action.

6. Execute the merged directive. Address the request directly. Do not announce which habits are being applied, explain the merge, or describe internal operations.

7. After execution, log all applied habits in one call:
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh log-exec '[{"scope":"<scope>","id":"<id>","override":"<request summary, max 80 chars>"}, ...]'
   ```
