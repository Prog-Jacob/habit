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
    [.[] | select(.type=="user") |
      {
        ts: (.timestamp // "" | if . != "" then (split("T")[1] // "" | split(".")[0] // "" | .[0:5]) else "??:??" end),
        text: (.message.content |
          if type == "string" then .
          elif type == "array" then [.[] | select(.type=="text") | .text] | join("\n")
          else "" end)
      }
      | .text |= gsub("^\\s+|\\s+$"; "")
      | select(.text | length > 0)
      | select(.text | test("^(<local-command|<command-|Base directory for this skill:|\\[Request interrupted)") | not)
    ] | .[-100:] | to_entries | map(
      "[" + ((.key + 1) | tostring) + " | " + .value.ts
      + (if (.value.text | test("habit|distill|plugin|/habit"; "i")) then " | plugin" else "" end)
      + "]\n" + .value.text
    ) | join("\n\n")
  ' "$1" 2>/dev/null
}

_resolve_transcript_path() {
  local arg="$1"
  if [ -f "$arg" ]; then echo "$arg"; return 0; fi
  local tp
  tp=$(read_state "$GLOBAL_DIR" | jq -r --arg sid "$arg" '.sessions[$sid].transcript_path // ""')
  [ -n "$tp" ] && [ -f "$tp" ] && { echo "$tp"; return 0; }
  return 1
}

cmd_read_transcript() {
  [ $# -eq 0 ] && { echo "No session data yet."; exit 0; }

  if [ $# -eq 1 ]; then
    local resolved
    resolved=$(_resolve_transcript_path "$1") || { echo "No session data yet."; exit 0; }
    _extract_user_messages "$resolved" || echo "No session data yet."
  else
    for arg in "$@"; do
      local resolved
      resolved=$(_resolve_transcript_path "$arg") || continue
      echo "---SESSION:$resolved---"
      _extract_user_messages "$resolved" || true
    done
  fi
}

cmd_read_pending_distill() {
  read_state "$GLOBAL_DIR" | jq '.meta.pending_sessions // []'
}

cmd_read_sessions() {
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

cmd_list_new_sessions() {
  local encoded_dir
  encoded_dir=$(echo "$PWD" | tr '/' '-')
  local project_dir="$HOME/.claude/projects/$encoded_dir"

  [ -d "$project_dir" ] || { echo "No project sessions found."; exit 0; }

  local watermarks
  watermarks=$(read_state "$GLOBAL_DIR" | jq -r '.meta.distilled_project_sessions // {}')

  local new_count=0
  for jsonl_file in "$project_dir"/*.jsonl; do
    [ -f "$jsonl_file" ] || continue
    local file_mtime stored_mtime
    file_mtime=$(_file_mtime "$jsonl_file")
    stored_mtime=$(echo "$watermarks" | jq -r --arg f "$jsonl_file" '.[$f] // ""')
    if [ "$stored_mtime" != "$file_mtime" ]; then
      echo "$jsonl_file"
      new_count=$((new_count + 1))
    fi
  done

  if [ "$new_count" -eq 0 ]; then echo "No new project sessions."; fi
}

cmd_check_triggers() {
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
