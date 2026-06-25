# learnings.sh: Persistent self-improvement overlay. Survives plugin updates
# because it lives in the data directory, not the version-pinned plugin cache.

cmd_write_learning() {
  local target="${1:-}" note="${2:-}" origin="${3:-}"
  [ -z "$target" ] && { echo "Error: target required" >&2; exit 1; }
  [ -z "$note" ] && { echo "Error: note required" >&2; exit 1; }
  ensure_dir "$GLOBAL_DIR"
  update_state "$GLOBAL_DIR" jq \
    --arg t "$target" --arg n "$note" --arg o "$origin" --arg ts "$(now_utc)" \
    '.learnings = ((.learnings // []) + [{target:$t, note:$n, origin:$o, created:$ts}])'
  echo "OK learning written"
}

cmd_read_learnings() {
  local target="${1:-}"
  read_state "$GLOBAL_DIR" | jq -r --arg t "$target" '
    [(.learnings // [])[] | select(.target == $t or .target == "global") | .note]
    | if length == 0 then "" else join("\n") end'
}

cmd_prune_learnings() {
  # De-dup by (target,note) keeping the first occurrence, then keep the last
  # LEARN_RETAIN. reduce preserves insertion order; group_by/unique_by would not.
  update_state "$GLOBAL_DIR" jq --argjson retain "$LEARN_RETAIN" '
    .learnings = ((.learnings // [])
      | reduce .[] as $l ([];
          if any(.[]; .target == $l.target and .note == $l.note) then . else . + [$l] end)
      | .[-$retain:])'
  echo "OK pruned learnings"
}
