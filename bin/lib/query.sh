# query.sh: Read-only queries against state.

cmd_read_meta() {
  local scope="${1:-global}"
  local dir
  dir=$(resolve_dir "$scope")
  read_state "$dir" | jq '.meta'
}

cmd_read_log() {
  jq -n -c \
    --argjson g "$(read_state "$GLOBAL_DIR")" \
    --argjson p "$(read_state "$PROJECT_DIR")" \
    '$g.log[], $p.log[]'
}

# Extract user messages from a Claude Code or Cursor JSONL transcript.
_extract_user_messages() {
  local file="$1"
  jq -rs '
    [.[] | select((.role // .type) == "user") |
      {
        ts: (.timestamp // "" | if . != "" then (split("T")[1] // "" | split(".")[0] // "" | .[0:5]) else "??:??" end),
        text: (.message.content // [] |
          if type == "string" then .
          elif type == "array" then [.[] | select(.type=="text") | .text] | join("\n")
          else "" end)
      }
      | .text |= (gsub("<timestamp>[^<]*</timestamp>"; "") | gsub("</?user_query>"; ""))
      | .text |= gsub("^\\s+|\\s+$"; "")
      | select(.text | length > 0)
      | select(.text | test("^(<local-command|<command-|Base directory for this skill:|\\[Request interrupted)") | not)
    ] | .[-100:] | to_entries | map(
      "[" + ((.key + 1) | tostring) + " | " + .value.ts
      + (if (.value.text | test("habit|distill|plugin|/habit"; "i")) then " | plugin" else "" end)
      + "]\n" + .value.text
    ) | join("\n\n")
  ' "$file" 2>/dev/null
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

cmd_list_new_sessions() {
  local sid="${1:-}"
  local state
  state=$(read_state "$GLOBAL_DIR")

  local watermarks pending exclude
  watermarks=$(echo "$state" | jq -r '(.meta.distilled_project_sessions // {}) | to_entries[] | "\(.key)\t\(.value)"')
  pending=$(echo "$state" | jq -r '[.meta.pending_sessions[]?.transcript_path] | join(" ")')
  exclude=$(echo "$state" | jq -r --arg sid "$sid" '.sessions[$sid].transcript_path // ""')

  local new_count=0
  local nl=$'\n' tab=$'\t'
  _emit_if_new() { # <path>
    local f="$1" mtime
    [ -f "$f" ] || return 0
    [ "$f" = "$exclude" ] && return 0
    mtime=$(_file_mtime "$f")
    case "$nl$watermarks$nl" in *"$nl$f$tab$mtime$nl"*) return 0;; esac
    case " $pending " in *" $f "*) return 0;; esac
    echo "$f"
    new_count=$((new_count + 1))
  }

  # Claude Code project sessions
  local project_dir
  project_dir=$(claude_project_dir)
  if [ -d "$project_dir" ]; then
    for jsonl_file in "$project_dir"/*.jsonl; do
      _emit_if_new "$jsonl_file"
    done
  fi

  # Cursor transcripts (skipped when ~/.cursor absent).
  if [ -d "$HOME/.cursor" ]; then
    while IFS= read -r f; do
      _emit_if_new "$f"
    done < <(cursor_transcript_files "$PWD")
  fi

  if [ "$new_count" -eq 0 ]; then echo "No new project sessions."; fi
}

cmd_check_triggers() {
  local session_id="${1:-}"

  local state
  state=$(read_state "$GLOBAL_DIR")

  local pc=0
  if [ -n "$session_id" ]; then
    pc=$(echo "$state" | jq -r --arg sid "$session_id" \
      '.sessions[$sid].prompt_count // 0 | if type == "number" then . else 0 end')
  fi

  local pending
  pending=$(echo "$state" | jq -r '(.meta.pending_sessions // []) | length')

  local has_new=0
  [ "$(cmd_list_new_sessions "$session_id")" = "No new project sessions." ] || has_new=1

  if [ "$pc" -ge "$PROMPT_THRESHOLD" ] || [ "$pending" -gt 0 ] || [ "$has_new" -eq 1 ]; then
    echo "Habit maintenance available: run the distill habit to process new sessions."
  fi
}
