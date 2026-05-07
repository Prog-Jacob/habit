# habit.sh: Habit CRUD operations.

# Resolve a habit id to "scope path" or return 1 if not found.
_resolve_habit() {
  local id="${1%% *}"
  if [ -f "$PROJECT_DIR/$id.md" ]; then
    echo "project $PROJECT_DIR/$id.md"
  elif [ -f "$GLOBAL_DIR/$id.md" ]; then
    echo "global $GLOBAL_DIR/$id.md"
  else
    return 1
  fi
}

_update_frontmatter_timestamp() {
  local habit_file="$1" timestamp="$2"
  [ -f "$habit_file" ] || return 0
  awk -v ts="$timestamp" 'NR<=20 && /^last_executed:/{next} NR<=20 && /^---$/{n++; if(n==2) print "last_executed: "ts} {print}' "$habit_file" \
    | atomic_write_file "$habit_file"
}

cmd_read_index() {
  local scope="${1:-merged}"
  local mode="${2:-}"

  local result
  case "$scope" in
    global|project)
      result=$(read_state "$(resolve_dir "$scope")" | jq '{entries: .index}')
      ;;
    merged)
      result=$(jq -n \
        --argjson g "$(read_state "$GLOBAL_DIR")" \
        --argjson p "$(read_state "$PROJECT_DIR")" \
        '{ entries: ([$g.index[], $p.index[]] | group_by(.id) | map(
          if length > 1 then (map(select(.scope == "project"))[0] // .[0]) else .[0] end
        )) }')
      ;;
    *) echo "Unknown scope: $scope" >&2; exit 1 ;;
  esac

  if [ "$mode" = "active" ]; then
    echo "$result" | jq '{entries: [.entries[] | select(.archived != true) | {id, tags, description, scope}]}'
  else
    echo "$result"
  fi
}

cmd_read_habit() {
  [ $# -eq 0 ] && { echo "NOT_FOUND"; exit 0; }

  if [ $# -eq 1 ]; then
    local resolved
    if resolved=$(_resolve_habit "$1"); then
      echo "SCOPE:${resolved%% *}"
      cat "${resolved#* }"
    else
      echo "NOT_FOUND"
    fi
  else
    for id in "$@"; do
      echo "---HABIT:$id---"
      local resolved
      if resolved=$(_resolve_habit "$id"); then
        echo "SCOPE:${resolved%% *}"
        cat "${resolved#* }"
      else
        echo "NOT_FOUND"
      fi
    done
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
  # Batch mode: first arg is JSON array
  if [[ "$1" == \[* ]]; then
    _log_exec_batch "$1"
    return
  fi

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
  _update_frontmatter_timestamp "$dir/$id.md" "$timestamp"

  echo "OK"
}

_log_exec_batch() {
  local entries_json="$1"
  local timestamp
  timestamp=$(now_utc)
  local count
  count=$(echo "$entries_json" | jq -r 'length')

  # Process each scope group with one update_state call per scope.
  for scope in $(echo "$entries_json" | jq -r '[.[].scope] | unique | .[]'); do
    local dir
    dir=$(resolve_dir "$scope")
    ensure_dir "$dir"

    local group
    group=$(echo "$entries_json" | jq -c --arg s "$scope" '[.[] | select(.scope == $s)]')

    local jq_expr='.index = [.index[] | if (.id as $id | $ids | index($id)) then .last_executed = $ts else . end]'
    local jq_args=(--arg ts "$timestamp" --argjson ids "$(echo "$group" | jq '[.[].id]')")

    local log_entries
    log_entries=$(echo "$group" | jq -c --arg ts "$timestamp" \
      '[.[] | select(.override != null and .override != "") | {id: .id, override: .override, timestamp: $ts, scope: .scope}]')

    if [ "$(echo "$log_entries" | jq 'length')" -gt 0 ]; then
      jq_args+=(--argjson log_entries "$log_entries")
      jq_expr="$jq_expr | .log += \$log_entries"
    fi

    update_state "$dir" jq "${jq_args[@]}" "$jq_expr"

    for id in $(echo "$group" | jq -r '.[].id'); do
      _update_frontmatter_timestamp "$dir/$id.md" "$timestamp"
    done
  done

  echo "OK logged $count"
}
