# common.sh: Shared constants and helpers for habit-tools.

PROJECT_DIR=".claude/habits"
GLOBAL_DIR="$HOME/.claude/habits"
STATE_FILE="settings.local.json"
DEFAULT_STATE='{"index":[],"meta":{"update_counter":0,"last_deep_timestamp":null},"log":[],"sessions":{}}'

LOG_RETAIN=25
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
