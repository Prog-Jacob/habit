#!/bin/bash
# habit-tools.sh: CLI for Habit file operations.
# All intelligence (classification, interpretation, dedup) is done by Claude.
# This script only handles mechanical file I/O.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/state.sh"
require_jq

cmd="${1:-}"; shift || true

case "$cmd" in
  session-init|session-end|prompt-tick|watch|read-prompt-count|reset-prompt-count)
    source "$SCRIPT_DIR/lib/session.sh" ;;
  read-index|read-habit|write-habit|log-exec)
    source "$SCRIPT_DIR/lib/frontmatter.sh"
    source "$SCRIPT_DIR/lib/habit.sh" ;;
  read-meta|read-log|read-transcript|read-sessions|list-new-sessions|read-pending-distill|check-triggers)
    source "$SCRIPT_DIR/lib/query.sh" ;;
  log-observation|read-observations|clear-observations)
    source "$SCRIPT_DIR/lib/observation.sh" ;;
  write-learning|read-learnings|prune-learnings)
    source "$SCRIPT_DIR/lib/learnings.sh" ;;
  env-context)
    cmd_env_context() {
      local root="${1:-$SCRIPT_DIR/..}"
      if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
         && git -C "$root" remote get-url origin 2>/dev/null | grep -qiE '[/:]habit(\.git)?/?$'; then
        echo "source"
      else
        echo "installed"
      fi
    }
    ;;
  read-shared)
    cmd_read_shared() { cat "$SCRIPT_DIR/../skills/habit-shared/${1:?filename required}"; }
    ;;
  distill-preload)
    source "$SCRIPT_DIR/lib/frontmatter.sh"
    source "$SCRIPT_DIR/lib/habit.sh"
    source "$SCRIPT_DIR/lib/query.sh"
    cmd_read_shared() { cat "$SCRIPT_DIR/../skills/habit-shared/${1:?filename required}"; }
    cmd_distill_preload() {
      local sid="${1:-}"
      # Each section is fault-isolated: one failing read (e.g. corrupt state)
      # must not abort the rest, or the skill's "run again" guidance loops forever.
      # Errors surface in the section body (2>&1) rather than being hidden.
      printf '===TRANSCRIPT===\n'; ( cmd_read_transcript "$sid" ) 2>/dev/null || true
      printf '\n===INDEX===\n'; cmd_read_index merged 2>&1 || true
      printf '\n===PENDING===\n'; cmd_read_pending_distill 2>&1 || true
      printf '\n===LOG===\n'; cmd_read_log 2>&1 || true
      printf '\n===META-GLOBAL===\n'; cmd_read_meta global 2>&1 || true
      printf '\n===META-PROJECT===\n'; cmd_read_meta project 2>&1 || true
      printf '\n===PROCESSING===\n'; cmd_read_shared PROCESSING.md 2>&1 || true
      printf '\n===OPERATIONS===\n'; cmd_read_shared OPERATIONS.md 2>&1 || true
    }
    ;;
  self-heal|reset-meta|prune-log|clear-pending-distill|mark-sessions-distilled)
    source "$SCRIPT_DIR/lib/frontmatter.sh"
    source "$SCRIPT_DIR/lib/maintenance.sh" ;;
  *)
    echo "Usage: habit-tools.sh <command> [args]" >&2
    echo "Commands: read-index, read-habit, read-meta, read-transcript, read-sessions, list-new-sessions, read-prompt-count, read-pending-distill, read-log, read-shared, env-context, distill-preload, session-init, session-end, prompt-tick, watch, reset-prompt-count, clear-pending-distill, mark-sessions-distilled, check-triggers, write-habit, log-exec, self-heal, reset-meta, prune-log, log-observation, read-observations, clear-observations, write-learning, read-learnings, prune-learnings" >&2
    exit 1
    ;;
esac

"cmd_${cmd//-/_}" "$@"
