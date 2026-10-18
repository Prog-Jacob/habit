# habit.sh: Habit CRUD operations.

# Resolve "<id> [override words]" to "scope path"; trims at first space, lowercases.
_resolve_habit() {
  local id="${1%% *}" pdir
  id=$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')
  pdir=$(project_dir) || pdir=""
  if [ -n "$pdir" ] && [ -f "$pdir/$id.md" ]; then
    echo "project $pdir/$id.md"
  elif [ -f "$GLOBAL_DIR/$id.md" ]; then
    echo "global $GLOBAL_DIR/$id.md"
  else
    return 1
  fi
}

_valid_id() {
  [[ "$1" =~ ^[a-z0-9-]{1,40}$ ]] || { echo "Invalid id: $1" >&2; exit 1; }
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

# Body length in characters: the text after the closing frontmatter line, trimmed.
habit_body_length() {
  printf '%s\n' "$1" | awk 'n >= 2 { print } /^---$/ { n++ }' | jq -Rs 'gsub("^\\s+|\\s+$"; "") | length'
}

# kind is rule or procedure (missing means procedure); a rule body stays short
# because every session loads it.
_check_kind() {
  local len
  case "$fm_kind" in
    ''|procedure) return 0 ;;
    rule) ;;
    *) echo "Invalid kind '$fm_kind' for $1: use rule or procedure" >&2; exit 1 ;;
  esac
  len=$(habit_body_length "$2")
  [ "$len" -le "$RULE_BODY_MAX" ] || {
    echo "Rule $1 body is $len characters; a rule body must be at most $RULE_BODY_MAX. Shorten it or make it kind: procedure." >&2
    exit 1
  }
}

cmd_write_habit() {
  local scope="$1"
  local id="$2"
  _valid_id "$id"
  local content="${3:-$(cat)}"

  local tmp
  tmp=$(mktemp)
  printf '%s\n' "$content" >"$tmp"
  parse_frontmatter "$tmp"
  rm -f "$tmp"
  [ "$fm_id" = "$id" ] || { echo "Frontmatter id '${fm_id:-missing}' does not match $id" >&2; exit 1; }
  [ -n "$fm_description" ] || { echo "Missing frontmatter description for $id" >&2; exit 1; }
  _check_kind "$id" "$content"

  local dir
  case "$scope" in
    global) dir="$GLOBAL_DIR" ;;
    project) dir=$(project_dir) || dir="$(project_new_root)/.claude/habits" ;;
    *) echo "Unknown scope: $scope" >&2; exit 1 ;;
  esac
  mkdir -p "$dir"
  local habit_file="$dir/$id.md"
  printf '%s\n' "$content" | atomic_write_file "$habit_file"
  echo "OK wrote $habit_file"
}

# delete-habit <scope> <id>: remove one habit file. Never creates dirs.
cmd_delete_habit() {
  local scope="${1:-}" id="${2:-}" dir
  _valid_id "$id"
  case "$scope" in
    global) dir="$GLOBAL_DIR" ;;
    project) dir=$(project_dir) || { echo "No project habits directory" >&2; exit 1; } ;;
    *) echo "Unknown scope: $scope" >&2; exit 1 ;;
  esac
  [ -f "$dir/$id.md" ] || { echo "No habit $id in $scope scope" >&2; exit 1; }
  rm -f "$dir/$id.md"
  echo "OK deleted $dir/$id.md"
}
