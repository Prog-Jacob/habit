#!/bin/bash
# habit-tools.sh: Lightweight CLI for Habit file operations.
# All intelligence (classification, interpretation, dedup) is done by Claude.
# This script only handles mechanical file I/O.

set -euo pipefail

GLOBAL_DIR="$HOME/.claude/habits"
# Relative to project root. This script is invoked by skills via
# ${CLAUDE_PLUGIN_ROOT}/bin/habit-tools.sh, which always runs from project root.
PROJECT_DIR=".claude/habits"

# --- Helpers ---

require_jq() {
  command -v jq &>/dev/null || { echo "Error: jq is required for this operation but not installed" >&2; exit 1; }
}

ensure_dir() {
  local dir="$1"
  [ -d "$dir" ] || mkdir -p "$dir"
}

ensure_file() {
  local file="$1" default="$2"
  [ -f "$file" ] || echo "$default" > "$file"
}

read_index_file() {
  local file="$1"
  if [ -f "$file" ]; then
    cat "$file"
  else
    echo '{"entries":[]}'
  fi
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

# Build a JSON index entry from a habit .md file. Requires jq.
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

# Write content to a file atomically via tmp+mv.
atomic_write() {
  local target="$1"
  local tmp
  tmp=$(mktemp)
  cat > "$tmp"
  mv "$tmp" "$target"
}

# --- Commands ---

cmd_read_index() {
  local scope="${1:---scope}"
  local value="${2:-merged}"
  # Handle both "--scope merged" and just "merged"
  if [ "$scope" = "--scope" ]; then
    scope="$value"
  fi

  case "$scope" in
    global)  read_index_file "$GLOBAL_DIR/_index.json" ;;
    project) read_index_file "$PROJECT_DIR/_index.json" ;;
    merged)
      local global project
      global=$(read_index_file "$GLOBAL_DIR/_index.json")
      project=$(read_index_file "$PROJECT_DIR/_index.json")
      # Merge: project entries shadow global entries with same id
      require_jq
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
  case "$scope" in
    global)  dir="$GLOBAL_DIR" ;;
    project) dir="$PROJECT_DIR" ;;
    *) echo "Unknown scope: $scope" >&2; exit 1 ;;
  esac

  if [ -f "$dir/_meta.json" ]; then
    cat "$dir/_meta.json"
  else
    echo '{"version":1,"update_counter":0,"last_deep_timestamp":null}'
  fi
}

cmd_read_habit() {
  # Parse: first token = id, rest preserved for Claude
  local id="${1:-}"
  [ -z "$id" ] && { echo "NOT_FOUND"; echo "No id provided"; exit 0; }

  # Strip everything after first whitespace for the id
  id=$(echo "$id" | awk '{print $1}')

  # Resolve: project first, then global
  if [ -f "$PROJECT_DIR/$id.md" ]; then
    echo "SCOPE:project"
    cat "$PROJECT_DIR/$id.md"
  elif [ -f "$GLOBAL_DIR/$id.md" ]; then
    echo "SCOPE:global"
    cat "$GLOBAL_DIR/$id.md"
  else
    echo "NOT_FOUND"
    # Output the merged index so Claude can do fuzzy matching
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
  cat "$GLOBAL_DIR/_log.jsonl" 2>/dev/null
  cat "$PROJECT_DIR/_log.jsonl" 2>/dev/null
}

cmd_read_transcript() {
  local session_id="${1:-}"
  [ -z "$session_id" ] && { echo "No session data yet."; exit 0; }

  local path_file="/tmp/habit-transcript-$session_id"
  [ -f "$path_file" ] || { echo "No session data yet."; exit 0; }

  local transcript_path
  transcript_path=$(cat "$path_file")
  [ -f "$transcript_path" ] || { echo "No session data yet."; exit 0; }

  require_jq
  jq -r 'select(.type=="user") | .message.content | if type == "string" then . elif type == "array" then map(select(.type=="text") | .text) | join("\n") else empty end' "$transcript_path" 2>/dev/null || echo "No session data yet."
}

# --- Write Operations ---

cmd_bump_counter() {
  require_jq
  local scope="$1"
  local dir
  case "$scope" in
    global)  dir="$GLOBAL_DIR" ;;
    project) dir="$PROJECT_DIR" ;;
    *) echo "Unknown scope: $scope" >&2; exit 1 ;;
  esac

  ensure_dir "$dir"
  ensure_file "$dir/_meta.json" '{"version":1,"update_counter":0,"last_deep_timestamp":null}'

  jq '.update_counter += 1' "$dir/_meta.json" | atomic_write "$dir/_meta.json"
}

cmd_write_habit() {
  local scope="$1"
  local id="$2"
  local dir
  case "$scope" in
    global)  dir="$GLOBAL_DIR" ;;
    project) dir="$PROJECT_DIR" ;;
    *) echo "Unknown scope: $scope" >&2; exit 1 ;;
  esac

  ensure_dir "$dir"

  local content
  content=$(cat)

  local habit_file="$dir/$id.md"
  printf '%s\n' "$content" | atomic_write "$habit_file"

  # Build index entry from the written file
  local entry
  entry=$(build_index_entry "$habit_file")

  # Update _index.json atomically
  local index_file="$dir/_index.json"
  ensure_file "$index_file" '{"entries":[]}'

  jq --argjson entry "$entry" \
    '.entries = [(.entries[] | select(.id != $entry.id)), $entry]' \
    "$index_file" | atomic_write "$index_file"

  cmd_bump_counter "$scope"

  echo "OK wrote $habit_file"
}

cmd_log_exec() {
  require_jq
  local scope="$1"
  local id="$2"
  local override="${3:-}"
  local dir
  case "$scope" in
    global)  dir="$GLOBAL_DIR" ;;
    project) dir="$PROJECT_DIR" ;;
    *) echo "Unknown scope: $scope" >&2; exit 1 ;;
  esac

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

  echo "$log_entry" >> "$dir/_log.jsonl"

  # Bump counter only if override was provided
  if [ -n "$override" ]; then
    cmd_bump_counter "$scope"
  fi

  echo "OK logged exec for $id"
}

# --- Self-Heal ---

cmd_self_heal() {
  local scope="$1"
  local dir
  case "$scope" in
    global)  dir="$GLOBAL_DIR" ;;
    project) dir="$PROJECT_DIR" ;;
    *) echo "Unknown scope: $scope" >&2; exit 1 ;;
  esac

  ensure_dir "$dir"
  ensure_file "$dir/_meta.json" '{"version":1,"update_counter":0,"last_deep_timestamp":null}'
  ensure_file "$dir/_log.jsonl" ""

  local entries_json="[]"
  local count=0

  for md_file in "$dir"/*.md; do
    [ -f "$md_file" ] || continue

    local entry
    entry=$(build_index_entry "$md_file")

    entries_json=$(echo "$entries_json" | jq --argjson entry "$entry" '. + [$entry]')
    count=$((count + 1))
  done

  jq -n --argjson entries "$entries_json" '{entries: $entries}' | atomic_write "$dir/_index.json"

  echo "OK rebuilt _index.json with $count entries"
}

# --- Main Router ---

cmd="${1:-}"
shift || true

case "$cmd" in
  read-index)     cmd_read_index "$@" ;;
  read-habit)     cmd_read_habit "$@" ;;
  read-meta)      cmd_read_meta "$@" ;;
  read-transcript) cmd_read_transcript "$@" ;;
  read-watch-state) cmd_read_watch_state "$@" ;;
  read-log)       cmd_read_log "$@" ;;
  write-habit)    cmd_write_habit "$@" ;;
  log-exec)       cmd_log_exec "$@" ;;
  bump-counter)   cmd_bump_counter "$@" ;;
  self-heal)      cmd_self_heal "$@" ;;
  *)
    echo "Usage: habit-tools.sh <command> [args]" >&2
    echo "Commands: read-index, read-habit, read-meta, read-transcript, read-watch-state, read-log, write-habit, log-exec, bump-counter, self-heal" >&2
    exit 1
    ;;
esac
