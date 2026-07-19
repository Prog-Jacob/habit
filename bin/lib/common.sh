# common.sh: Shared constants and helpers for habit-tools.

PROJECT_DIR=".claude/habits"
GLOBAL_DIR="$HOME/.claude/habits"
STATE_FILE="settings.local.json"
DEFAULT_STATE='{"index":[],"meta":{"update_counter":0,"last_deep_timestamp":null,"distilled_project_sessions":{}},"log":[],"sessions":{},"observations":[],"learnings":[]}'

LOG_RETAIN=25
LEARN_RETAIN=40
PROMPT_THRESHOLD=20

require_jq() {
  command -v jq &>/dev/null || { echo "Error: jq is required but not installed" >&2; exit 1; }
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

_file_mtime() { stat -f "%m" "$1" 2>/dev/null || stat -c "%Y" "$1"; }

# Cursor transcript files for a workspace (excludes subagent transcripts).
cursor_transcript_files() {
  local workspace="${1:-$PWD}"
  local dir="$HOME/.cursor/projects/$(echo "${workspace#/}" | tr '/' '-')/agent-transcripts"
  find "$dir" -maxdepth 2 -name "*.jsonl" -not -path "*/subagents/*" 2>/dev/null
}

# Claude Code project dir for a workspace (slugified path).
claude_project_dir() { echo "$HOME/.claude/projects/$(echo "${1:-$PWD}" | tr '/' '-')"; }

# Most recent Cursor transcript for a workspace, or empty.
cursor_transcript_path() {
  local found
  found=$(cursor_transcript_files "${1:-$PWD}")
  [ -z "$found" ] && { echo ""; return 0; }
  echo "$found" | xargs ls -t 2>/dev/null | head -1 || echo ""
}

# Per-session breadcrumbs under sessions.d/<sid>, plus a best-effort `current`
# (last-started). Skills source the newest sessions.d entry.
breadcrumb_path() { echo "$GLOBAL_DIR/current"; }
session_breadcrumb_path() { echo "$GLOBAL_DIR/sessions.d/$1"; }

write_breadcrumb() {
  local session_id="${1:-}"
  mkdir -p "$GLOBAL_DIR/sessions.d"
  local body
  body=$(printf 'HABIT_BIN=%s\nHABIT_SID=%s\n' "$SCRIPT_DIR/habit-tools.sh" "$session_id")
  printf '%s' "$body" | atomic_write_file "$(session_breadcrumb_path "$session_id")"
  printf '%s' "$body" | atomic_write_file "$(breadcrumb_path)"
  # Reap breadcrumbs from sessions that never ended: same 24h cutoff as state.
  find "$GLOBAL_DIR/sessions.d" -type f -mmin +1440 -delete 2>/dev/null || true
}

# Remove this session's breadcrumb; clear `current` only if it matches.
clear_breadcrumb() {
  local session_id="${1:-}"
  [ -n "$session_id" ] && rm -f "$(session_breadcrumb_path "$session_id")" 2>/dev/null
  if grep -q "^HABIT_SID=${session_id}\$" "$(breadcrumb_path)" 2>/dev/null; then
    rm -f "$(breadcrumb_path)" 2>/dev/null || true
  fi
}
