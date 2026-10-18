#!/bin/bash
# Habit hook dispatcher for Claude Code and Cursor. Routes session-start and
# capture to habit-tools.sh with the hook JSON payload on stdin.
# Always exits 0 and prints nothing: hooks must never block.

EVENT="${1:-}"
case "$EVENT" in session-start|capture) ;; *) cat >/dev/null 2>&1; exit 0 ;; esac
INPUT=$(cat 2>/dev/null || echo "")

# Prefer the host's plugin root (Cursor first; it may also set the Claude alias).
SCRIPT_DIR="${CURSOR_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
[ -f "$SCRIPT_DIR/bin/habit-tools.sh" ] || SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HABIT_BIN="$SCRIPT_DIR/bin/habit-tools.sh"
[ -f "$HABIT_BIN" ] || exit 0

# Cursor waits on its hooks, so capture backgrounds itself there.
if [ "$EVENT" = capture ] && { [ -n "${CURSOR_PLUGIN_ROOT:-}" ] || [[ "$INPUT" == *'"cursor_version"'* ]]; }; then
  printf '%s' "$INPUT" | bash "$HABIT_BIN" capture >/dev/null 2>&1 &
else
  printf '%s' "$INPUT" | bash "$HABIT_BIN" "$EVENT" >/dev/null 2>&1
fi
exit 0
