---
name: habit-distill
description: "Use when the user wants to extract reusable patterns from their session, restructure the habit inventory, or scan all project sessions for patterns. Triggers on: distill, sweep session, extract patterns, clean up habits, inventory maintenance."
argument-hint: "[maintain | project]"
context: fork
allowed-tools: Bash(bash:*)
disable-model-invocation: true
---

# Habit Distill: Sweep & Restructure

Runs in a forked subagent. Use only the commands in the Operations reference for writes. Summaries must be human-friendly. Do not mention file names, counters, timestamps, or pruning stats.

## Setup

Run this once and reuse the values below. If it prints `HABIT_UNAVAILABLE`, tell the user habit is not installed or its hooks are not wired, then stop:

```bash
source "$HOME/.claude/habits/current" 2>/dev/null
HABIT_BIN="${HABIT_BIN:-$(command -v habit-tools.sh || echo "${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin/habit-tools.sh}")}"
[ -f "${HABIT_BIN:-}" ] || echo "HABIT_UNAVAILABLE: habit is not wired on this host."
```

## Preload (required precondition)

Run this ONE command and read its full output before doing anything else. Do NOT route, classify, write, or summarize until it has returned in full:

```bash
bash "$HABIT_BIN" distill-preload "$HABIT_SID"
```

The output has delimited sections, in order: `===TRANSCRIPT===` (this session's user prompts), `===INDEX===` (merged index), `===PENDING===` (prior sessions), `===LOG===` (execution log), `===META-GLOBAL===`, `===META-PROJECT===`, `===PROCESSING===` (the processing rules), `===OPERATIONS===` (the operations reference). If any section is missing, run the command again before continuing.

## Routing

The argument is the user's message (`maintain`, `project`, or empty).

**Before routing:** if the message contains feedback about the plugin beyond the routing keyword, log each piece as an observation first:

```bash
bash "$HABIT_BIN" log-observation "$HABIT_SID" '<feedback>'
```

Pick the first matching branch. Do not read or execute other branches. **Only the Project branch may call `list-new-sessions` and `read-sessions`.** Maintain and Regular work only with the preloaded data.

1. Message contains "project" go to Project.
2. Message contains "maintain", "pending", or "deep" go to Maintain.
3. Message empty go to Regular.

---

## Project

Scan new or modified project sessions incrementally, then restructure. This branch loads session data fresh; the preloaded transcript does not apply here, but the other preloaded sections (index, log, metadata, processing, operations) still do.

1. List: `bash "$HABIT_BIN" list-new-sessions`. If "No new project sessions." or "No project sessions found.", return that and stop.
2. Collect the file paths (one per line). Split into batches of 5.
3. Per batch, load `bash "$HABIT_BIN" read-transcript <p1> ... <p5>`, run Sweep, then `bash "$HABIT_BIN" mark-sessions-distilled <p1> ... <p5>`.
4. Run Restructure.
5. Run Self-improve.
6. Run Cleanup.
7. Summary opening line: "Scanned N new project sessions."

## Maintain

Sweep plus full restructure plus self-improvement, using the preloaded transcript and pending sessions only.

1. If the preloaded transcript and pending list are both empty, skip to step 3.
2. Collect pending transcript paths, fetch in one call `bash "$HABIT_BIN" read-transcript <p1> ...`, run Sweep on current plus pending if usable prompts exist.
3. Run Restructure.
4. Run Self-improve.
5. Run Cleanup.
6. Summary opening line: "Swept current session and N pending." or "No new session data to sweep. Ran inventory maintenance."

## Regular

Using the preloaded transcript and pending sessions only.

1. If both empty, return "Nothing to extract yet." and stop.
2. Fetch pending transcripts (same call as Maintain step 2). If zero usable prompts, return "Nothing to extract yet." and stop.
3. Run Sweep.
4. If `update_counter >= 20` in either scope (from the preloaded metadata), continue at Maintain step 3.
5. Run Cleanup.
6. Summary, same opening-line rule as Maintain.

---

## Summary Format

Opening line per branch, then: one sentence per new habit; one per merge; categories of skipped prompts or that sweep was skipped; override findings; inventory health; self-improve result or "No observations pending."

## Sweep

1. Apply the Processing Rules: classify, interpret, dedup, structure. Extract the generalizable principle, scope it.
2. Write or merge each reusable pattern via `write-habit`.
3. Check the log for override patterns (3+ similar on one habit). List them.
4. Verify each written habit with `read-habit <id>`: valid frontmatter, verb-first description under 120 chars, self-contained instruction. Rewrite if not.
5. Verify unique ids, lowercase singular tags, no two habits with identical behavior.
6. Flag plugin friction as observations via `log-observation`.

## Restructure

- Merge convergent habits; re-compare merged results.
- Normalize tags (`ts` to `typescript`, `js` to `javascript`). Rename ids violating `[a-z0-9-]`; flag renames.
- Archive stale (never executed AND created 30+ days ago AND not updated 30+ days).
- Act on override patterns: scoped variants or base updates.
- Quality check descriptions, tags, instructions.
- Rebuild: `bash "$HABIT_BIN" self-heal global` and `... self-heal project`.
- Reset meta: `bash "$HABIT_BIN" reset-meta global` and `... reset-meta project`.
- Prune log: `bash "$HABIT_BIN" prune-log global` and `... prune-log project`.

## Self-improve

Run `bash "$HABIT_BIN" read-observations`. If none, skip. For each observation, identify the responsible plugin source file, read it, apply the smallest fix, preserve style. If none maps clearly, skip and note it.

## Cleanup

```bash
bash "$HABIT_BIN" clear-pending-distill
bash "$HABIT_BIN" clear-observations
bash "$HABIT_BIN" reset-prompt-count "$HABIT_SID"
```
