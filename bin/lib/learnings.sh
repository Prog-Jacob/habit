# learnings.sh: Self-improvement overlay in learnings.jsonl. Lines are only
# appended; forgetting appends a {forget: <id>} tombstone and reads fold it.

# Active learnings as one JSON array, oldest first.
_active_learnings() {
  { if [ -f "$GLOBAL_DIR/learnings.jsonl" ]; then cat "$GLOBAL_DIR/learnings.jsonl"; fi; } | jq -ncR '
    [inputs | fromjson? | select(type == "object")]
    | (map(.forget // empty)) as $gone
    | map(select(.id != null and .forget == null and (.id as $i | any($gone[]; . == $i) | not)))'
}

_append_learning_line() {
  mkdir -p "$GLOBAL_DIR"
  printf '%s\n' "$1" >> "$GLOBAL_DIR/learnings.jsonl"
}

cmd_write_learning() {
  local target="${1:-}" note="${2:-}" origin="${3:-}"
  [ -z "$target" ] && { echo "Error: target required" >&2; exit 1; }
  [ -z "$note" ] && { echo "Error: note required" >&2; exit 1; }
  _append_learning_line "$(jq -nc --arg id "$(date +%s)-$RANDOM$RANDOM" \
    --arg t "$target" --arg n "$note" --arg o "$origin" \
    '{id: $id, ts: (now | todate), target: $t, note: $n, origin: $o}')"
  echo "OK learning written"
}

cmd_read_learnings() {
  _active_learnings | jq -r --arg t "${1:-}" \
    '[.[] | select(.target == $t or .target == "global") | .note] | if length == 0 then empty else join("\n") end'
}

cmd_list_learnings() {
  _active_learnings | jq -r 'to_entries[] | "\(.key + 1). [\(.value.target)] \(.value.note)"'
}

cmd_forget_learning() {
  local n="${1:-}" id
  case "$n" in ''|*[!0-9]*) echo "Usage: forget-learning <n>" >&2; exit 1 ;; esac
  id=$(_active_learnings | jq -r --argjson n "$n" 'if $n >= 1 then .[$n - 1].id // empty else empty end')
  [ -n "$id" ] || { echo "No learning number $n" >&2; exit 1; }
  _append_learning_line "$(jq -nc --arg id "$id" '{forget: $id, ts: (now | todate)}')"
  echo "OK forgot learning $n"
}
