# habit.sh: Habit CRUD operations.

cmd_read_index() {
  local scope="${1:-merged}"

  case "$scope" in
    global|project)
      read_state "$(resolve_dir "$scope")" | jq '{entries: .index}'
      ;;
    merged)
      jq -n \
        --argjson g "$(read_state "$GLOBAL_DIR")" \
        --argjson p "$(read_state "$PROJECT_DIR")" \
        '{ entries: ([$g.index[], $p.index[]] | group_by(.id) | map(
          if length > 1 then (map(select(.scope == "project"))[0] // .[0]) else .[0] end
        )) }'
      ;;
    *) echo "Unknown scope: $scope" >&2; exit 1 ;;
  esac
}

cmd_read_habit() {
  local id="${1:-}"
  [ -z "$id" ] && { echo "NOT_FOUND"; echo "No id provided"; exit 0; }

  id="${id%% *}"

  if [ -f "$PROJECT_DIR/$id.md" ]; then
    echo "SCOPE:project"
    cat "$PROJECT_DIR/$id.md"
  elif [ -f "$GLOBAL_DIR/$id.md" ]; then
    echo "SCOPE:global"
    cat "$GLOBAL_DIR/$id.md"
  else
    echo "NOT_FOUND"
    echo "--- INDEX ---"
    cmd_read_index merged
  fi
}

cmd_write_habit() {
  local scope="$1"
  local id="$2"
  [[ "$id" =~ ^[a-z0-9-]{1,40}$ ]] || { echo "Invalid id: $id" >&2; exit 1; }
  local dir
  dir=$(resolve_dir "$scope")

  ensure_dir "$dir"

  local content="${3:-$(cat)}"

  local habit_file="$dir/$id.md"
  printf '%s\n' "$content" | atomic_write_file "$habit_file"

  local entry
  entry=$(build_index_entry "$habit_file")

  update_state "$dir" jq --argjson entry "$entry" \
    '.index = [(.index[] | select(.id != $entry.id)), $entry] | .meta.update_counter += 1'

  echo "OK wrote $habit_file"
}

cmd_log_exec() {
  local scope="$1"
  local id="$2"
  local override="${3:-}"
  local dir
  dir=$(resolve_dir "$scope")

  ensure_dir "$dir"

  local timestamp
  timestamp=$(now_utc)

  local jq_expr='.index = [.index[] | if .id == $id then .last_executed = $ts else . end]'
  local jq_args=(--arg id "$id" --arg ts "$timestamp")

  if [ -n "$override" ]; then
    local log_entry
    log_entry=$(jq -n \
      --arg id "$id" \
      --arg override "$override" \
      --arg timestamp "$timestamp" \
      --arg scope "$scope" \
      '{id: $id, override: $override, timestamp: $timestamp, scope: $scope}')
    jq_args+=(--argjson entry "$log_entry")
    jq_expr="$jq_expr | .log += [\$entry]"
  fi

  update_state "$dir" jq "${jq_args[@]}" "$jq_expr"

  # Update last_executed in the .md file to keep frontmatter in sync.
  local habit_file="$dir/$id.md"
  if [ -f "$habit_file" ]; then
    awk -v ts="$timestamp" 'NR<=20 && /^last_executed:/{next} NR<=20 && /^---$/{n++; if(n==2) print "last_executed: "ts} {print}' "$habit_file" \
      | atomic_write_file "$habit_file"
  fi

  echo "OK logged exec for $id"
}
