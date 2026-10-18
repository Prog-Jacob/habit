# common.sh: Shared constants and helpers for habit-tools.

GLOBAL_DIR="$HOME/.claude/habits"
# Limits read by other libs.
# shellcheck disable=SC2034
INBOX_CAP=400 RULE_BODY_MAX=600 RULES_BUDGET=8000
JQ_MISSING="habit needs jq. Install it (macOS: brew install jq, Debian or Ubuntu: sudo apt install jq), then start a new session."

require_jq() {
  command -v jq &>/dev/null || { echo "$JQ_MISSING" >&2; exit 1; }
}

# Hidden temp file beside the target, so mv is a same-filesystem rename and
# globs over the directory never see a partial write.
atomic_write_file() {
  local target="$1"
  local tmp
  tmp=$(mktemp "$(dirname "$target")/.$(basename "$target").XXXXXX") || return 1
  if ! { cat > "$tmp" && mv "$tmp" "$target"; }; then
    rm -f "$tmp"; return 1
  fi
}

# epoch_from <file>: the epoch the file holds, or fail when absent or malformed.
epoch_from() {
  local e
  e=$(cat "$1" 2>/dev/null) || return 1
  case "$e" in ''|*[!0-9]*) return 1 ;; esac
  echo "$e"
}

# Captured files not yet distilled: inbox/*.jsonl and unfinished claimed runs.
inbox_files() {
  local f
  for f in "$GLOBAL_DIR"/inbox/*.jsonl "$GLOBAL_DIR"/inbox/.claimed/*/*.jsonl; do
    if [ -f "$f" ]; then echo "$f"; fi
  done
}
