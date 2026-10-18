#!/bin/bash
# Habit hook dispatcher for Claude Code and Cursor. Routes session-start,
# capture and pre-compact to habit-tools.sh with the hook JSON payload on stdin.
# Always exits 0 with stderr silent: hooks must never block. Only a JSON
# object from session-start (rules and the distill notice) or pre-compact
# (the notice) reaches stdout.

EVENT="${1:-}"
case "$EVENT" in session-start|capture|pre-compact) ;; *) cat >/dev/null 2>&1; exit 0 ;; esac
INPUT=$(cat 2>/dev/null || echo "")

# Prefer the host's plugin root (Cursor first; it may also set the Claude alias).
SCRIPT_DIR="${CURSOR_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
[ -f "$SCRIPT_DIR/bin/habit-tools.sh" ] || SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HABIT_BIN="$SCRIPT_DIR/bin/habit-tools.sh"
[ -f "$HABIT_BIN" ] || exit 0

if [ "$EVENT" != capture ]; then
  OUT=$(printf '%s' "$INPUT" | bash "$HABIT_BIN" "$EVENT" 2>/dev/null)
  case "$OUT" in '{'*'}') printf '%s\n' "$OUT" ;; esac
elif [ -n "${CURSOR_PLUGIN_ROOT:-}" ] || [[ "$INPUT" == *'"cursor_version"'* ]]; then
  # Cursor waits on its hooks, so capture backgrounds itself there.
  printf '%s' "$INPUT" | bash "$HABIT_BIN" capture >/dev/null 2>&1 &
else
  printf '%s' "$INPUT" | bash "$HABIT_BIN" capture >/dev/null 2>&1
fi
exit 0
