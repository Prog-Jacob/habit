#!/bin/bash
# Habit hook dispatcher for Claude Code and Cursor.
# Routes session-init / prompt-tick / session-end to habit-tools.sh.
# Reads the hook JSON payload from stdin. Always exits 0. Hooks must never block.

INPUT=$(cat 2>/dev/null || echo "")
EVENT="${1:-}"
[ -z "$EVENT" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HABIT_BIN="$SCRIPT_DIR/bin/habit-tools.sh"
[ -f "$HABIT_BIN" ] || exit 0

# Reuse the shared Cursor transcript locator.
# shellcheck source=/dev/null
source "$SCRIPT_DIR/bin/lib/common.sh" 2>/dev/null || true

_field() { echo "$INPUT" | jq -r ".$1 // \"\"" 2>/dev/null || echo ""; }
_breadcrumb_sid() { sed -n 's/^HABIT_SID=//p' "$(breadcrumb_path 2>/dev/null)" 2>/dev/null || echo ""; }
_sid() {
  local s; s="$(_field session_id)"; [ -z "$s" ] && s="$(_field conversation_id)"
  [ -z "$s" ] && s="$(_breadcrumb_sid)"; echo "$s"
}

case "$EVENT" in
  session-init)
    SID="$(_field session_id)"; [ -z "$SID" ] && SID="$(_field conversation_id)"
    [ -z "$SID" ] && SID="cursor-$(date +%s)-$$"
    bash "$HABIT_BIN" session-init "$SID" >/dev/null 2>&1 || true
    ;;
  prompt-tick)
    SID="$(_sid)"; [ -z "$SID" ] && exit 0
    PROMPT="$(_field prompt)"; [ -z "$PROMPT" ] && exit 0
    TRANSCRIPT="$(_field transcript_path)"
    [ -z "$TRANSCRIPT" ] && TRANSCRIPT="$(cursor_transcript_path "${PWD:-$HOME}" 2>/dev/null || echo "")"
    bash "$HABIT_BIN" prompt-tick "$SID" "$TRANSCRIPT" "$PROMPT" >/dev/null 2>&1 || true
    ;;
  session-end)
    SID="$(_sid)"; [ -z "$SID" ] && exit 0
    bash "$HABIT_BIN" session-end "$SID" >/dev/null 2>&1 || true
    ;;
esac

exit 0
