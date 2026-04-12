#!/bin/bash
# habit-tools.sh: CLI for Habit file operations.
# All intelligence (classification, interpretation, dedup) is done by Claude.
# This script only handles mechanical file I/O.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/state.sh"

cmd="${1:-}"; shift || true

case "$cmd" in
  session-init|session-end|prompt-tick|watch|read-prompt-count|reset-prompt-count)
    source "$SCRIPT_DIR/lib/session.sh" ;;
  read-index|read-habit|write-habit|log-exec)
    source "$SCRIPT_DIR/lib/frontmatter.sh"
    source "$SCRIPT_DIR/lib/habit.sh" ;;
  read-meta|read-log|read-transcript|read-pending-distill|check-triggers)
    source "$SCRIPT_DIR/lib/query.sh" ;;
  self-heal|reset-meta|prune-log|clear-pending-distill)
    source "$SCRIPT_DIR/lib/frontmatter.sh"
    source "$SCRIPT_DIR/lib/maintenance.sh" ;;
  *)
    echo "Usage: habit-tools.sh <command> [args]" >&2
    echo "Commands: read-index, read-habit, read-meta, read-transcript, read-prompt-count, read-pending-distill, read-log, session-init, session-end, prompt-tick, watch, reset-prompt-count, clear-pending-distill, check-triggers, write-habit, log-exec, self-heal, reset-meta, prune-log" >&2
    exit 1
    ;;
esac

"cmd_${cmd//-/_}" "$@"
