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
# Auto-detects Claude Code format (type=="user") vs Cursor format (role=="user").
# Cursor wraps prompts in <timestamp>/<user_query> tags, which are stripped.
# Filters system noise, trims whitespace, caps at 100 messages.
_extract_user_messages() {
  local file="$1"
  local content
  content=$(cat "$file" 2>/dev/null) || { return 1; }
  local first_line
  first_line=$(echo "$content" | grep -m1 '^{')
  if echo "$first_line" | jq -e '.role != null' >/dev/null 2>&1; then
    echo "$content" | jq -rs '
      [.[] | select(.role=="user") |
        {
          ts: (.timestamp // "" | if . != "" then (split("T")[1] // "" | split(".")[0] // "" | .[0:5]) else "??:??" end),
          text: (.message.content // [] | [.[] | select(.type=="text") | .text] | join("\n"))
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
    ' 2>/dev/null
  else
    echo "$content" | jq -rs '
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
    ' 2>/dev/null
  fi
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
    _extract_user_messages "$jsonl_file" || true
    found=$((found + 1))
  done

  if [ "$found" -eq 0 ]; then echo "No project sessions found."; fi
}

cmd_list_new_sessions() {
  local state
  state=$(read_state "$GLOBAL_DIR")
  local watermarks pending
  watermarks=$(echo "$state" | jq -r '.meta.distilled_project_sessions // {}')
  pending=$(echo "$state" | jq -r '[.meta.pending_sessions[]?.transcript_path] | join(" ")')

  local new_count=0
  _emit_if_new() { # <path>
    local f="$1" mtime stored
    [ -f "$f" ] || return 0
    mtime=$(_file_mtime "$f")
    stored=$(echo "$watermarks" | jq -r --arg f "$f" '.[$f] // ""')
    [ "$stored" = "$mtime" ] && return 0
    case " $pending " in *" $f "*) return 0;; esac
    echo "$f"
    new_count=$((new_count + 1))
  }

  # Claude Code project sessions
  local encoded_dir project_dir
  encoded_dir=$(echo "$PWD" | tr '/' '-')
  project_dir="$HOME/.claude/projects/$encoded_dir"
  if [ -d "$project_dir" ]; then
    for jsonl_file in "$project_dir"/*.jsonl; do
      _emit_if_new "$jsonl_file"
    done
  fi

  # Cursor agent transcripts for this workspace (canonical paths, no /..)
  while IFS= read -r f; do
    _emit_if_new "$f"
  done < <(cursor_transcript_files "$PWD")

  if [ "$new_count" -eq 0 ]; then echo "No new project sessions."; fi
}

cmd_check_triggers() {
  local session_id="${1:-}"

  local state
  state=$(read_state "$GLOBAL_DIR")

  # Coerce to an integer in jq: a corrupt non-numeric prompt_count would
  # otherwise abort the bash `-ge` test under `set -euo pipefail`.
  local pc=0
  if [ -n "$session_id" ]; then
    pc=$(echo "$state" | jq -r --arg sid "$session_id" \
      '.sessions[$sid].prompt_count // 0 | if type == "number" then . else 0 end')
  fi

  local pending
  pending=$(echo "$state" | jq -r '(.meta.pending_sessions // []) | length')

  # Fire when there is unprocessed input: the current session crossed the
  # prompt threshold, prior sessions are pending, or new project sessions exist.
  local has_new=0
  [ "$(cmd_list_new_sessions)" = "No new project sessions." ] || has_new=1

  if [ "$pc" -ge "$PROMPT_THRESHOLD" ] || [ "$pending" -gt 0 ] || [ "$has_new" -eq 1 ]; then
    echo "Habit maintenance available. Run \`/habit:distill\` to process."
  fi
}
