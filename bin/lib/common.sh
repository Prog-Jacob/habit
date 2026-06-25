# common.sh: Shared constants and helpers for habit-tools.

PROJECT_DIR=".claude/habits"
GLOBAL_DIR="$HOME/.claude/habits"
STATE_FILE="settings.local.json"
DEFAULT_STATE='{"index":[],"meta":{"update_counter":0,"last_deep_timestamp":null,"distilled_project_sessions":{}},"log":[],"sessions":{},"observations":[],"learnings":[]}'

LOG_RETAIN=25
LEARN_RETAIN=40
LOG_TRIGGER=50
PROMPT_THRESHOLD=20

require_jq() {
  command -v jq &>/dev/null || { echo "Error: jq is required but not installed" >&2; exit 1; }
}

ensure_dir() {
  [ -d "$1" ] || mkdir -p "$1"
}

resolve_dir() {
  case "$1" in
    global)  echo "$GLOBAL_DIR" ;;
    project) echo "$PROJECT_DIR" ;;
    *) echo "Unknown scope: $1" >&2; exit 1 ;;
  esac
}

require_scope_dir() {
  local dir
  dir=$(resolve_dir "$1")
  [ -d "$dir" ] || { echo "No habits directory for scope: $1"; return 1; }
  echo "$dir"
}

require_session_id() {
  [ -n "${1:-}" ] && return 0
  echo "Error: session id required" >&2; exit 1
}

now_utc() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

if stat -f "%m" /dev/null &>/dev/null 2>&1; then
  _file_mtime() { stat -f "%m" "$1"; }
else
  _file_mtime() { stat -c "%Y" "$1"; }
fi

# List every Cursor agent transcript for a workspace, newest-agnostic.
# Cursor stores transcripts at agent-transcripts/<uuid>/<uuid>.jsonl (nested);
# subagent transcripts are excluded. Single source of the path scheme and find.
# Usage: cursor_transcript_files [workspace_path]
cursor_transcript_files() {
  local workspace="${1:-$PWD}"
  local dir="$HOME/.cursor/projects/$(echo "${workspace#/}" | tr '/' '-')/agent-transcripts"
  find "$dir" -maxdepth 2 -name "*.jsonl" -not -path "*/subagents/*" 2>/dev/null
}

# Most recent Cursor agent transcript for a workspace, or empty.
# Usage: cursor_transcript_path [workspace_path]
cursor_transcript_path() {
  local found
  found=$(cursor_transcript_files "${1:-$PWD}")
  [ -z "$found" ] && { echo ""; return 0; }
  echo "$found" | xargs ls -t 2>/dev/null | head -1 || echo ""
}

# Session breadcrumb: lets skills resolve the tool path and session id portably,
# independent of host (Claude Code or Cursor). Lives in the existing data dir.
# Written by the session-start hook path; read by skills via `source`.
breadcrumb_path() { echo "$GLOBAL_DIR/current"; }

write_breadcrumb() {
  local session_id="${1:-}"
  ensure_dir "$GLOBAL_DIR"
  local body
  body=$(printf 'HABIT_BIN=%s\nHABIT_SID=%s\n' "$SCRIPT_DIR/habit-tools.sh" "$session_id")
  printf '%s' "$body" | atomic_write_file "$(breadcrumb_path)"
}

clear_breadcrumb() { rm -f "$(breadcrumb_path)" 2>/dev/null || true; }
