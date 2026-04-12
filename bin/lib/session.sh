# session.sh: Session lifecycle and watch control.

cmd_session_init() {
  require_jq
  require_session_id "${1:-}"
  local session_id="$1"
  ensure_dir "$GLOBAL_DIR"
  update_state "$GLOBAL_DIR" jq --arg sid "$session_id" \
    '.sessions[$sid] = ((.sessions[$sid] // {}) + {watch_paused: false})
     | .sessions[$sid].prompt_count = (.sessions[$sid].prompt_count // 0)
     | .sessions[$sid].transcript_path = (.sessions[$sid].transcript_path // "")'
  echo "OK session initialized"
}

cmd_session_end() {
  require_jq
  require_session_id "${1:-}"
  local session_id="$1"
  ensure_dir "$GLOBAL_DIR"

  local info
  info=$(read_state "$GLOBAL_DIR" | jq -r --arg sid "$session_id" \
    '[(.sessions[$sid].prompt_count // 0), (.sessions[$sid].transcript_path // "")] | @tsv')
  local pc tp
  pc=$(echo "$info" | cut -f1)
  tp=$(echo "$info" | cut -f2)

  if [ "$pc" -gt 0 ] && [ -n "$tp" ] && [ -f "$tp" ]; then
    local timestamp
    timestamp=$(now_utc)
    update_state "$GLOBAL_DIR" jq \
      --arg sid "$session_id" --arg tp "$tp" --argjson pc "$pc" --arg ts "$timestamp" \
      '.meta.pending_sessions = ((.meta.pending_sessions // []) + [{session_id: $sid, transcript_path: $tp, prompt_count: $pc, timestamp: $ts}])
       | del(.sessions[$sid])'
  else
    update_state "$GLOBAL_DIR" jq --arg sid "$session_id" 'del(.sessions[$sid])'
  fi

  echo "OK session ended"
}

cmd_prompt_tick() {
  require_jq
  require_session_id "${1:-}"
  local session_id="$1"
  local transcript="${2:-}"
  local prompt="${3:-}"

  [ -z "$prompt" ] && exit 0
  local words
  words=$(echo "$prompt" | wc -w | tr -d ' ')
  [ "$words" -lt 5 ] && exit 0

  update_state "$GLOBAL_DIR" jq --arg sid "$session_id" --arg tp "$transcript" \
    'if (.sessions[$sid].watch_paused // false) then .
     else .sessions[$sid].prompt_count = ((.sessions[$sid].prompt_count // 0) + 1)
     | if $tp != "" then .sessions[$sid].transcript_path = $tp else . end end'
  echo "OK"
}

cmd_watch() {
  local verb="${1:-status}"
  local session_id="${2:-}"

  case "$verb" in
    start)
      require_session_id "$session_id"
      update_state "$GLOBAL_DIR" jq --arg sid "$session_id" \
        '.sessions[$sid].watch_paused = false'
      echo "OK watch resumed"
      ;;
    stop)
      require_session_id "$session_id"
      update_state "$GLOBAL_DIR" jq --arg sid "$session_id" \
        '.sessions[$sid].watch_paused = true'
      echo "OK watch paused"
      ;;
    status)
      [ -z "$session_id" ] && { echo "ACTIVE"; exit 0; }
      require_jq
      local paused
      paused=$(read_state "$GLOBAL_DIR" | jq -r --arg sid "$session_id" '.sessions[$sid].watch_paused // false')
      [ "$paused" = "true" ] && echo "PAUSED" || echo "ACTIVE"
      ;;
    *) echo "Usage: watch <start|stop|status> [session_id]" >&2; exit 1 ;;
  esac
}

cmd_read_prompt_count() {
  require_jq
  local session_id="${1:-}"
  [ -z "$session_id" ] && { echo "0"; exit 0; }
  read_state "$GLOBAL_DIR" | jq -r --arg sid "$session_id" '.sessions[$sid].prompt_count // 0'
}

cmd_reset_prompt_count() {
  require_jq
  require_session_id "${1:-}"
  update_state "$GLOBAL_DIR" jq --arg sid "$1" \
    '.sessions[$sid].prompt_count = 0'
  echo "OK counter reset"
}
