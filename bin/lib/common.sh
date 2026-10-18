# common.sh: Shared constants and helpers for habit-tools.

GLOBAL_DIR="$HOME/.claude/habits"
INBOX_CAP=400

require_jq() {
  command -v jq &>/dev/null || { echo "Error: jq is required but not installed" >&2; exit 1; }
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

# Captured files not yet distilled: inbox/*.jsonl and unfinished claimed runs.
inbox_files() {
  local f
  for f in "$GLOBAL_DIR"/inbox/*.jsonl "$GLOBAL_DIR"/inbox/.claimed/*/*.jsonl; do
    if [ -f "$f" ]; then echo "$f"; fi
  done
}
