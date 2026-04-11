#!/bin/bash
# habit-tools.sh: Lightweight CLI for Habit file operations.
# All intelligence (classification, interpretation, dedup) is done by Claude.
# This script only handles mechanical file I/O.

set -euo pipefail

GLOBAL_DIR="$HOME/.claude/habits"
# Relative to project root. This script is invoked by skills via
# ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh, which always runs from project root.
PROJECT_DIR=".claude/habits"
STATE_FILE="settings.local.json"
DEFAULT_STATE='{"index":[],"meta":{"update_counter":0,"last_deep_timestamp":null},"log":[]}'

# Must match the separator hardcoded in hooks/habit-watch-gate.sh
QUEUE_SEPARATOR="---HABIT_SEPARATOR---"
QUEUE_THRESHOLD=20
LOG_TRIGGER=50
LOG_RETAIN=25

# --- Helpers ---

require_jq() {
  command -v jq &>/dev/null || { echo "Error: jq is required for this operation but not installed" >&2; exit 1; }
}

ensure_dir() {
  local dir="$1"
  [ -d "$dir" ] || mkdir -p "$dir"
}

# Read the state file for a scope dir, or return default if missing.
read_state() {
  require_jq
  local dir="$1"
  if [ -f "$dir/$STATE_FILE" ]; then
    cat "$dir/$STATE_FILE"
  else
    echo "$DEFAULT_STATE"
  fi
}

# Write stdin to a file atomically via tmp+mv.
atomic_write_file() {
  local target="$1"
  local tmp
  tmp=$(mktemp)
  cat > "$tmp"
  mv "$tmp" "$target"
}

# Write state atomically.
write_state() {
  local dir="$1"
  atomic_write_file "$dir/$STATE_FILE"
}

# Read state, pipe through a transform command, write back.
# Usage: update_state "$dir" jq [flags...] 'expression'
update_state() {
  local dir="$1"; shift
  read_state "$dir" | "$@" | write_state "$dir"
}

# Extract YAML frontmatter block (between --- delimiters) from a habit .md file.
extract_frontmatter() {
  local file="$1"
  sed -n '/^---$/,/^---$/p' "$file" | sed '1d;$d'
}

# Parse a single field from frontmatter text (passed via stdin).
fm_field() {
  local field="$1"
  grep "^${field}:" | head -1 | sed "s/^${field}: *//"
}

# Build a JSON index entry from a habit .md file.
build_index_entry() {
  require_jq
  local file="$1"
  local fm
  fm=$(extract_frontmatter "$file")

  local fm_id fm_tags fm_description fm_scope fm_created fm_updated fm_archived fm_last_executed
  fm_id=$(echo "$fm" | fm_field "id")
  fm_tags=$(echo "$fm" | fm_field "tags" | sed 's/^\[//;s/\]$//')
  fm_description=$(echo "$fm" | fm_field "description" | sed 's/^"//;s/"$//')
  fm_scope=$(echo "$fm" | fm_field "scope")
  fm_created=$(echo "$fm" | fm_field "created")
  fm_updated=$(echo "$fm" | fm_field "updated")
  fm_archived=$(echo "$fm" | fm_field "archived")
  fm_last_executed=$(echo "$fm" | fm_field "last_executed")

  local tags_json="[]"
  if [ -n "$fm_tags" ]; then
    tags_json=$(echo "$fm_tags" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | jq -R . | jq -s .)
  fi

  local archived_val="false"
  [ "$fm_archived" = "true" ] && archived_val="true"

  jq -n \
    --arg id "$fm_id" \
    --argjson tags "$tags_json" \
    --arg description "$fm_description" \
    --arg scope "$fm_scope" \
    --arg created "$fm_created" \
    --arg updated "$fm_updated" \
    --argjson archived "$archived_val" \
    --arg last_executed "$fm_last_executed" \
    '{id: $id, tags: $tags, description: $description, scope: $scope, created: $created, updated: $updated, archived: $archived}
     | if $last_executed != "" then .last_executed = $last_executed else . end'
}

# Resolve scope string to directory path.
resolve_dir() {
  local scope="$1"
  case "$scope" in
    global)  echo "$GLOBAL_DIR" ;;
    project) echo "$PROJECT_DIR" ;;
    *) echo "Unknown scope: $scope" >&2; exit 1 ;;
  esac
}

# Parse --scope argument. Accepts "--scope <value>" or bare "<value>".
# First arg is the default when nothing is provided.
parse_scope_arg() {
  local default="$1"; shift
  local first="${1:---scope}"
  local second="${2:-$default}"
  [ "$first" = "--scope" ] && echo "$second" || echo "$first"
}

# Resolve scope to dir and verify it exists.
# Returns dir path on stdout. Returns 1 if dir missing.
require_scope_dir() {
  local scope="$1"
  local dir
  dir=$(resolve_dir "$scope")
  [ -d "$dir" ] || { echo "No habits directory for scope: $scope"; return 1; }
  echo "$dir"
}

# Require a non-empty session id. Exit 1 with error if missing.
require_session_id() {
  [ -n "${1:-}" ] && return 0
  echo "Error: session id required" >&2; exit 1
}

# UTC timestamp in ISO 8601.
now_utc() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# Build session temp file path: /tmp/habit-<type>-<session_id>
session_path() {
  echo "/tmp/habit-$1-$2"
}

# --- Read Commands ---

cmd_read_index() {
  local scope
  scope=$(parse_scope_arg "merged" "$@")

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

cmd_read_meta() {
  local scope
  scope=$(parse_scope_arg "global" "$@")

  local dir
  dir=$(resolve_dir "$scope")
  read_state "$dir" | jq '.meta'
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
    cmd_read_index --scope merged
  fi
}

cmd_read_watch_state() {
  local session_id="${1:-}"
  [ -z "$session_id" ] && { echo "INACTIVE"; exit 0; }
  [ -f "$(session_path watch-active "$session_id")" ] && echo "ACTIVE" || echo "INACTIVE"
}

cmd_watch_start() {
  require_session_id "${1:-}"
  local session_id="$1"
  touch "$(session_path watch-active "$session_id")"
  touch "$(session_path watch-queue "$session_id")"
  echo "OK watch started"
}

cmd_watch_stop() {
  require_session_id "${1:-}"
  local session_id="$1"
  rm -f "$(session_path watch-active "$session_id")"
  echo "OK watch stopped"
}

cmd_clear_watch_queue() {
  require_session_id "${1:-}"
  local session_id="$1"
  : > "$(session_path watch-queue "$session_id")"
  echo "OK queue cleared"
}

cmd_read_watch_queue() {
  local session_id="${1:-}"
  [ -z "$session_id" ] && { echo "No queued prompts."; exit 0; }
  local queue
  queue=$(session_path watch-queue "$session_id")
  [ -f "$queue" ] && [ -s "$queue" ] && cat "$queue" || echo "No queued prompts."
}

cmd_check_triggers() {
  local session_id="${1:-}"

  local qc=0
  if [ -n "$session_id" ]; then
    local queue
    queue=$(session_path watch-queue "$session_id")
    if [ -f "$queue" ] && [ -s "$queue" ]; then
      qc=$(grep -c "$QUEUE_SEPARATOR" "$queue" 2>/dev/null || echo "0")
    fi
  fi

  jq -n \
    --argjson g "$(read_state "$GLOBAL_DIR")" \
    --argjson p "$(read_state "$PROJECT_DIR")" \
    --argjson qt "$QUEUE_THRESHOLD" \
    --argjson lt "$LOG_TRIGGER" \
    --argjson qc "$qc" \
    'if ($g.meta.update_counter // 0) >= $qt or ($p.meta.update_counter // 0) >= $qt
     then "TRIGGERS: deep"
     elif ($g.log | length) >= $lt or ($p.log | length) >= $lt or $qc >= $qt
     then "TRIGGERS: distill"
     else "TRIGGERS: none" end' -r
}

cmd_read_log() {
  jq -n \
    --argjson g "$(read_state "$GLOBAL_DIR")" \
    --argjson p "$(read_state "$PROJECT_DIR")" \
    '[$g.log[], $p.log[]] | .[]' -c
}

cmd_read_transcript() {
  local arg="${1:-}"
  [ -z "$arg" ] && { echo "No session data yet."; exit 0; }

  local transcript_path=""

  if [ -f "$arg" ]; then
    transcript_path="$arg"
  else
    local path_file
    path_file=$(session_path transcript "$arg")
    [ -f "$path_file" ] || { echo "No session data yet."; exit 0; }
    transcript_path=$(cat "$path_file")
    [ -f "$transcript_path" ] || { echo "No session data yet."; exit 0; }
  fi

  require_jq
  # Extract user messages. [-100:] caps context size in long sessions.
  jq -s '[.[] | select(.type=="user")] | .[-100:] | .[] | .message.content | if type == "string" then . elif type == "array" then map(select(.type=="text") | .text) | join("\n") else empty end' "$transcript_path" 2>/dev/null || echo "No session data yet."
}

# --- Write Commands ---

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

  local habit_file="$dir/$id.md"
  if [ -f "$habit_file" ]; then
    awk -v ts="$timestamp" '/^last_executed:/{next} /^---$/{n++; if(n==2) print "last_executed: "ts} {print}' "$habit_file" \
      | atomic_write_file "$habit_file"
  fi

  echo "OK logged exec for $id"
}

# --- Deep Distill Maintenance ---

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

# --- Self-Heal ---

cmd_self_heal() {
  local dir
  dir=$(require_scope_dir "$1") || { echo "$dir"; exit 0; }

  local entries_json
  entries_json=$(
    for md_file in "$dir"/*.md; do
      [ -f "$md_file" ] || continue
      build_index_entry "$md_file"
    done | jq -s '.'
  )
  local count
  count=$(echo "$entries_json" | jq 'length')

  update_state "$dir" jq --argjson entries "$entries_json" '.index = $entries'

  echo "OK rebuilt index with $count entries"
}

# --- Main Router ---

cmd="${1:-}"
shift || true

case "$cmd" in
  read-index)       cmd_read_index "$@" ;;
  read-habit)       cmd_read_habit "$@" ;;
  read-meta)        cmd_read_meta "$@" ;;
  read-transcript)  cmd_read_transcript "$@" ;;
  read-watch-state) cmd_read_watch_state "$@" ;;
  read-watch-queue) cmd_read_watch_queue "$@" ;;
  watch-start)      cmd_watch_start "$@" ;;
  watch-stop)       cmd_watch_stop "$@" ;;
  clear-watch-queue) cmd_clear_watch_queue "$@" ;;
  check-triggers)   cmd_check_triggers "$@" ;;
  read-log)         cmd_read_log "$@" ;;
  write-habit)      cmd_write_habit "$@" ;;
  log-exec)         cmd_log_exec "$@" ;;
  self-heal)        cmd_self_heal "$@" ;;
  reset-meta)       cmd_reset_meta "$@" ;;
  prune-log)        cmd_prune_log "$@" ;;
  *)
    echo "Usage: habit-tools.sh <command> [args]" >&2
    echo "Commands: read-index, read-habit, read-meta, read-transcript, read-watch-state, read-watch-queue, watch-start, watch-stop, clear-watch-queue, check-triggers, read-log, write-habit, log-exec, self-heal, reset-meta, prune-log" >&2
    exit 1
    ;;
esac
