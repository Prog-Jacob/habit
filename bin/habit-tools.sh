#!/bin/bash
# habit-tools.sh: CLI for Habit file operations.
# All intelligence (classification, interpretation, dedup) is done by the model.
# This script only handles mechanical file I/O.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/project.sh"
source "$SCRIPT_DIR/lib/migrate.sh"
require_jq

_habit_libs() {
  source "$SCRIPT_DIR/lib/frontmatter.sh"
  source "$SCRIPT_DIR/lib/usage-log.sh"
  source "$SCRIPT_DIR/lib/index.sh"
  source "$SCRIPT_DIR/lib/habit.sh"
}

_migrate_libs() {
  source "$SCRIPT_DIR/lib/capture.sh"
  source "$SCRIPT_DIR/lib/usage-log.sh"
  source "$SCRIPT_DIR/lib/index.sh"
  source "$SCRIPT_DIR/lib/snapshot.sh"
}

_status_libs() {
  _habit_libs
  source "$SCRIPT_DIR/lib/snapshot.sh"
  source "$SCRIPT_DIR/lib/learnings.sh"
  source "$SCRIPT_DIR/lib/nudge.sh"
  source "$SCRIPT_DIR/lib/watch.sh"
  source "$SCRIPT_DIR/lib/status.sh"
}

cmd="${1:-}"; shift || true

case "$cmd" in
  read-index|invalid-habits|read-habit|write-habit|delete-habit|log-exec|read-log)
    _habit_libs ;;
  capture)
    source "$SCRIPT_DIR/lib/capture.sh" ;;
  session-start)
    _migrate_libs
    source "$SCRIPT_DIR/lib/shim.sh"
    source "$SCRIPT_DIR/lib/nudge.sh"
    source "$SCRIPT_DIR/lib/rules.sh" ;;
  pre-compact)
    source "$SCRIPT_DIR/lib/nudge.sh" ;;
  migrate)
    _migrate_libs ;;
  claim|finish|undo)
    source "$SCRIPT_DIR/lib/snapshot.sh"
    source "$SCRIPT_DIR/lib/inbox.sh" ;;
  write-learning|read-learnings|list-learnings|forget-learning)
    source "$SCRIPT_DIR/lib/learnings.sh" ;;
  status|watch)
    _status_libs ;;
  preload)
    _status_libs
    source "$SCRIPT_DIR/lib/rules.sh"
    source "$SCRIPT_DIR/lib/context.sh"
    source "$SCRIPT_DIR/lib/preload.sh" ;;
  context-files)
    source "$SCRIPT_DIR/lib/context.sh" ;;
  snapshot)
    source "$SCRIPT_DIR/lib/snapshot.sh" ;;
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
  *)
    echo "Usage: habit-tools.sh <command> [args]" >&2
    echo "Commands: preload, read-index, invalid-habits, read-habit, write-habit, delete-habit, log-exec, read-log, write-learning, read-learnings, list-learnings, forget-learning, status, watch, claim, finish, undo, snapshot, context-files, capture, session-start, pre-compact, migrate, env-context" >&2
    exit 1
    ;;
esac

# Lazy migration: hooks and pure lookups skip it; everything else migrates
# first when .v3 is missing or the current project still has a v2 log.
# status only observes, so it reports a missing .v3 instead of fixing it.
case "$cmd" in
  capture|session-start|pre-compact|status|migrate|env-context) ;;
  *)
    if [ ! -f "$GLOBAL_DIR/.v3" ] || _migrate_project_pending >/dev/null; then
      _migrate_libs
      migrate_if_needed inline >/dev/null 2>&1 || true
    fi
    ;;
esac

"cmd_${cmd//-/_}" "$@"
