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
DEFAULT_STATE='{"index":[],"meta":{"version":1,"update_counter":0,"last_deep_timestamp":null},"log":[]}'

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

  local fm_id fm_tags fm_description fm_scope fm_created fm_updated fm_archived
  fm_id=$(echo "$fm" | fm_field "id")
  fm_tags=$(echo "$fm" | fm_field "tags" | sed 's/^\[//;s/\]$//')
  fm_description=$(echo "$fm" | fm_field "description" | sed 's/^"//;s/"$//')
  fm_scope=$(echo "$fm" | fm_field "scope")
  fm_created=$(echo "$fm" | fm_field "created")
  fm_updated=$(echo "$fm" | fm_field "updated")
  fm_archived=$(echo "$fm" | fm_field "archived")

  local tags_json="[]"
  if [ -n "$fm_tags" ]; then
    tags_json=$(echo "$fm_tags" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | jq -R . | jq -s .)
  fi

  local archived_val="false"
  if [ "$fm_archived" = "true" ]; then
    archived_val="true"
  fi

  jq -n \
    --arg id "$fm_id" \
    --argjson tags "$tags_json" \
    --arg description "$fm_description" \
    --arg scope "$fm_scope" \
    --arg created "$fm_created" \
    --arg updated "$fm_updated" \
    --argjson archived "$archived_val" \
    '{id: $id, tags: $tags, description: $description, scope: $scope, created: $created, updated: $updated, archived: $archived}'
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

# --- Read Commands ---

cmd_read_index() {
  local scope="${1:---scope}"
  local value="${2:-merged}"
  if [ "$scope" = "--scope" ]; then
    scope="$value"
  fi

  case "$scope" in
    global)
      read_state "$GLOBAL_DIR" | jq '{entries: .index}'
      ;;
    project)
      read_state "$PROJECT_DIR" | jq '{entries: .index}'
      ;;
    merged)
      local global project
      global=$(read_state "$GLOBAL_DIR" | jq '{entries: .index}')
      project=$(read_state "$PROJECT_DIR" | jq '{entries: .index}')
      jq -n \
        --argjson g "$global" \
        --argjson p "$project" \
        '{ entries: ([$g.entries[], $p.entries[]] | group_by(.id) | map(
          if length > 1 then (map(select(.scope == "project"))[0] // .[0]) else .[0] end
        )) }'
      ;;
    *) echo "Unknown scope: $scope" >&2; exit 1 ;;
  esac
}

cmd_read_meta() {
  local scope="${1:---scope}"
  local value="${2:-global}"
  if [ "$scope" = "--scope" ]; then
    scope="$value"
  fi

  local dir
  dir=$(resolve_dir "$scope")
  read_state "$dir" | jq '.meta'
}

cmd_read_habit() {
  local id="${1:-}"
  [ -z "$id" ] && { echo "NOT_FOUND"; echo "No id provided"; exit 0; }

  id=$(echo "$id" | awk '{print $1}')

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
  [ -f "/tmp/habit-watch-active-$session_id" ] && echo "ACTIVE" || echo "INACTIVE"
}

cmd_read_log() {
  read_state "$GLOBAL_DIR" | jq -c '.log[]' 2>/dev/null || true
  read_state "$PROJECT_DIR" | jq -c '.log[]' 2>/dev/null || true
}

cmd_read_transcript() {
  local arg="${1:-}"
  [ -z "$arg" ] && { echo "No session data yet."; exit 0; }

  local transcript_path=""

  if [ -f "$arg" ]; then
    transcript_path="$arg"
  else
    local path_file="/tmp/habit-transcript-$arg"
    [ -f "$path_file" ] || { echo "No session data yet."; exit 0; }
    transcript_path=$(cat "$path_file")
    [ -f "$transcript_path" ] || { echo "No session data yet."; exit 0; }
  fi

  require_jq
  # Extract user messages. The jq slurp takes all user messages, then [-30:]
  # keeps the last 30 to cap context size in long sessions.
  jq -s '[.[] | select(.type=="user")] | .[-30:] | .[] | .message.content | if type == "string" then . elif type == "array" then map(select(.type=="text") | .text) | join("\n") else empty end' "$transcript_path" 2>/dev/null || echo "No session data yet."
}

# --- Write Commands ---

cmd_write_habit() {
  local scope="$1"
  local id="$2"
  local dir
  dir=$(resolve_dir "$scope")

  ensure_dir "$dir"

  local content
  content=$(cat)

  local habit_file="$dir/$id.md"
  printf '%s\n' "$content" | atomic_write_file "$habit_file"

  local entry
  entry=$(build_index_entry "$habit_file")

  local state
  state=$(read_state "$dir")

  # Update index: remove old entry with same id, add new one. Bump counter.
  echo "$state" | jq \
    --argjson entry "$entry" \
    '.index = [(.index[] | select(.id != $entry.id)), $entry] | .meta.update_counter += 1' \
    | write_state "$dir"

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
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local override_val="null"
  if [ -n "$override" ]; then
    override_val=$(printf '%s' "$override" | jq -R .)
  fi

  local log_entry
  log_entry=$(jq -n \
    --arg id "$id" \
    --argjson override "$override_val" \
    --arg timestamp "$timestamp" \
    --arg scope "$scope" \
    '{id: $id, override: $override, timestamp: $timestamp, scope: $scope}')

  local state
  state=$(read_state "$dir")

  # Append to log. Bump counter only if override was provided.
  local bump=0
  [ -n "$override" ] && bump=1

  echo "$state" | jq \
    --argjson entry "$log_entry" \
    --argjson bump "$bump" \
    '.log += [$entry] | .meta.update_counter += $bump' \
    | write_state "$dir"

  echo "OK logged exec for $id"
}

# --- Self-Heal ---

cmd_self_heal() {
  local scope="$1"
  local dir
  dir=$(resolve_dir "$scope")

  [ -d "$dir" ] || { echo "No habits directory for scope: $scope"; exit 0; }

  local entries_json="[]"
  local count=0

  for md_file in "$dir"/*.md; do
    [ -f "$md_file" ] || continue

    local entry
    entry=$(build_index_entry "$md_file")

    entries_json=$(echo "$entries_json" | jq --argjson entry "$entry" '. + [$entry]')
    count=$((count + 1))
  done

  # Preserve existing log and meta, rebuild index only
  local state
  state=$(read_state "$dir")

  echo "$state" | jq --argjson entries "$entries_json" '.index = $entries' \
    | write_state "$dir"

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
  read-log)         cmd_read_log "$@" ;;
  write-habit)      cmd_write_habit "$@" ;;
  log-exec)         cmd_log_exec "$@" ;;
  self-heal)        cmd_self_heal "$@" ;;
  *)
    echo "Usage: habit-tools.sh <command> [args]" >&2
    echo "Commands: read-index, read-habit, read-meta, read-transcript, read-watch-state, read-log, write-habit, log-exec, self-heal" >&2
    exit 1
    ;;
esac
