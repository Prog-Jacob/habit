# maintenance.sh: Index rebuilding, metadata reset, log pruning.

cmd_clear_pending_distill() {
  update_state "$GLOBAL_DIR" jq '.meta.pending_sessions = []'
  echo "OK pending cleared"
}

cmd_reset_meta() {
  local dir
  dir=$(require_scope_dir "$1") || { echo "$dir"; exit 0; }

  update_state "$dir" jq --arg ts "$(now_utc)" \
    '.meta.update_counter = 0 | .meta.last_deep_timestamp = $ts'

  echo "OK reset meta for $1"
}

cmd_prune_log() {
  local dir
  dir=$(require_scope_dir "$1") || { echo "$dir"; exit 0; }

  update_state "$dir" jq --argjson retain "$LOG_RETAIN" \
    '.log = .log[-$retain:]'

  echo "OK pruned log for $1"
}

cmd_self_heal() {
  local dir
  dir=$(require_scope_dir "$1") || { echo "$dir"; exit 0; }

  local entries_json
  entries_json=$(
    for md_file in "$dir"/*.md; do
      [ -f "$md_file" ] || continue
      build_index_entry "$md_file"
    done | jq -s '. // []'
  )
  local count
  count=$(echo "$entries_json" | jq 'length')

  update_state "$dir" jq --argjson entries "$entries_json" '.index = $entries'

  echo "OK rebuilt index with $count entries"
}

cmd_mark_sessions_distilled() {
  local watermarks="{}"
  for f in "$@"; do
    [ -f "$f" ] || continue
    local mtime
    mtime=$(_file_mtime "$f")
    watermarks=$(echo "$watermarks" | jq --arg f "$f" --arg m "$mtime" '.[$f] = $m')
  done
  update_state "$GLOBAL_DIR" jq --argjson w "$watermarks" \
    '.meta.distilled_project_sessions = ((.meta.distilled_project_sessions // {}) + $w)'
  echo "OK marked $(echo "$watermarks" | jq 'length') sessions"
}
