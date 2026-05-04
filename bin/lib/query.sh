# query.sh: Read-only queries against state.

cmd_read_meta() {
  local scope="${1:-global}"
  local dir
  dir=$(resolve_dir "$scope")
  read_state "$dir" | jq '.meta'
}

cmd_read_log() {
  jq -n \
    --argjson g "$(read_state "$GLOBAL_DIR")" \
    --argjson p "$(read_state "$PROJECT_DIR")" \
    '[$g.log[], $p.log[]] | .[]' -c
}

# Extract clean user messages from a JSONL transcript file.
# Filters system noise, trims whitespace, caps at 100 messages.
_extract_user_messages() {
  jq -rs '
    [.[] | select(.type=="user") | .message.content
     | if type == "string" then .
       elif type == "array" then map(select(.type=="text") | .text) | join("\n")
       else empty end
     | gsub("^\\s+|\\s+$"; "")
     | select(length > 0)
     | select(test("^(<local-command|<command-|Base directory for this skill:|\\[Request interrupted)") | not)
    ] | .[-100:] | join("\n")
  ' "$1" 2>/dev/null
}

cmd_read_transcript() {
  require_jq
  local arg="${1:-}"
  [ -z "$arg" ] && { echo "No session data yet."; exit 0; }

  local transcript_path=""

  if [ -f "$arg" ]; then
    transcript_path="$arg"
  else
    local tp
    tp=$(read_state "$GLOBAL_DIR" | jq -r --arg sid "$arg" '.sessions[$sid].transcript_path // ""')
    [ -n "$tp" ] && [ -f "$tp" ] && transcript_path="$tp"
  fi

  [ -z "$transcript_path" ] && { echo "No session data yet."; exit 0; }

  _extract_user_messages "$transcript_path" || echo "No session data yet."
}

cmd_read_pending_distill() {
  require_jq
  read_state "$GLOBAL_DIR" | jq '.meta.pending_sessions // []'
}

cmd_read_sessions() {
  require_jq
  local encoded_dir
  encoded_dir=$(echo "$PWD" | tr '/' '-')
  local project_dir="$HOME/.claude/projects/$encoded_dir"

  [ -d "$project_dir" ] || { echo "No project sessions found."; exit 0; }

  local found=0
  for jsonl_file in "$project_dir"/*.jsonl; do
    [ -f "$jsonl_file" ] || continue
    [ "$found" -gt 0 ] && echo "---SESSION---"
    _extract_user_messages "$jsonl_file"
    found=$((found + 1))
  done

  [ "$found" -eq 0 ] && echo "No project sessions found."
}

cmd_check_triggers() {
  require_jq
  local session_id="${1:-}"

  local state
  state=$(read_state "$GLOBAL_DIR")
  local pc=0
  if [ -n "$session_id" ]; then
    pc=$(echo "$state" | jq -r --arg sid "$session_id" '.sessions[$sid].prompt_count // 0')
  fi

  local pending
  pending=$(echo "$state" | jq -r '(.meta.pending_sessions // []) | length')
  [ "$pending" -gt 0 ] && pending=1 || pending=0

  jq -n \
    --argjson g "$state" \
    --argjson p "$(read_state "$PROJECT_DIR")" \
    --argjson pt "$PROMPT_THRESHOLD" \
    --argjson lt "$LOG_TRIGGER" \
    --argjson pc "$pc" \
    --argjson pending "$pending" \
    'if ($g.meta.update_counter // 0) >= $pt or ($p.meta.update_counter // 0) >= $pt
     or ($g.log | length) >= $lt or ($p.log | length) >= $lt or $pc >= $pt
     or $pending > 0
   then "Habit maintenance available. Run `/habit:distill` to process."
   else "" end' -r
}

cmd_should_pending() {
  require_jq
  jq -n \
    --argjson g "$(read_state "$GLOBAL_DIR")" \
    --argjson p "$(read_state "$PROJECT_DIR")" \
    --argjson pt "$PROMPT_THRESHOLD" \
    'if ($g.meta.update_counter // 0) >= $pt or ($p.meta.update_counter // 0) >= $pt
     then "yes" else "no" end' -r
}
