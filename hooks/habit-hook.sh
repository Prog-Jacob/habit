#!/bin/bash
# Habit hook dispatcher for Claude Code and Cursor.
# Routes session-init / prompt-tick / session-end to habit-tools.sh.
# Reads the hook JSON payload from stdin. Always exits 0. Hooks must never block.

INPUT=$(cat 2>/dev/null || echo "")
EVENT="${1:-}"
[ -z "$EVENT" ] && exit 0

# Resolve symlinks so install.sh's symlink into ~/.cursor/hooks still finds the repo.
SELF="$0"
while [ -L "$SELF" ]; do
  LINK="$(readlink "$SELF")"
  case "$LINK" in /*) SELF="$LINK" ;; *) SELF="$(dirname "$SELF")/$LINK" ;; esac
done
# Prefer the host's plugin root (Cursor first; it may also set the Claude alias).
SCRIPT_DIR="${CURSOR_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
[ -f "$SCRIPT_DIR/bin/habit-tools.sh" ] || SCRIPT_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
HABIT_BIN="$SCRIPT_DIR/bin/habit-tools.sh"
[ -f "$HABIT_BIN" ] || exit 0

# shellcheck source=/dev/null
source "$SCRIPT_DIR/bin/lib/common.sh" 2>/dev/null || true

# One jq pass: extract all payload fields. \x1f delimiter survives empty fields
# (tab-IFS would not); strip embedded \x1f and flatten prompt whitespace.
SID="" PROMPT="" TRANSCRIPT="" WORKSPACE=""
IFS=$'\x1f' read -r SID PROMPT TRANSCRIPT WORKSPACE < <(
  echo "$INPUT" | jq -r '[((.session_id // .conversation_id // "") | gsub("\\x{1f}"; "")), ((.prompt // "") | gsub("[\\n\\t\\x{1f}]+"; " ")), ((.transcript_path // "") | gsub("\\x{1f}"; "")), ((.workspace_roots[0] // "") | gsub("\\x{1f}"; ""))] | @tsv | gsub("\t"; "\u001f")' 2>/dev/null
) || true

_breadcrumb_sid() { sed -n 's/^HABIT_SID=//p' "$(breadcrumb_path 2>/dev/null)" 2>/dev/null || echo ""; }

case "$EVENT" in
  session-init)
    [ -z "$SID" ] && SID="cursor-$(date +%s)-$$"
    bash "$HABIT_BIN" session-init "$SID" >/dev/null 2>&1 || true
    ;;
  prompt-tick)
    [ -z "$SID" ] && SID="$(_breadcrumb_sid)"
    [ -z "$SID" ] && exit 0
    [ -z "$PROMPT" ] && exit 0
    # Fallback for hosts that omit transcript_path. Cursor user-hooks run from
    # ~/.cursor/, so derive the workspace from the payload, not $PWD.
    if [ -z "$TRANSCRIPT" ]; then
      TRANSCRIPT="$(cursor_transcript_path "${WORKSPACE:-${PWD:-$HOME}}" 2>/dev/null || echo "")"
    fi
    bash "$HABIT_BIN" prompt-tick "$SID" "$TRANSCRIPT" "$PROMPT" >/dev/null 2>&1 || true
    ;;
  session-end)
    [ -z "$SID" ] && SID="$(_breadcrumb_sid)"
    [ -z "$SID" ] && exit 0
    bash "$HABIT_BIN" session-end "$SID" >/dev/null 2>&1 || true
    ;;
esac

exit 0
