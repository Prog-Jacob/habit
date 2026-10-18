# habit.sh: Habit CRUD operations.

# Resolve "<id> [override words]" to "scope path"; trims at first space, lowercases.
_resolve_habit() {
  local id="${1%% *}" pdir
  id=$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')
  [[ "$id" =~ ^[a-z0-9-]{1,40}$ ]] || return 1
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
  local id resolved
  for id in "$@"; do
    [ $# -eq 1 ] || echo "---HABIT:${id%% *}---"
    if resolved=$(_resolve_habit "$id"); then
      echo "SCOPE:${resolved%% *}"
      cat "${resolved#* }"
    else
      echo "NOT_FOUND"
    fi
  done
}

# _check_habit <id> <file>: the frontmatter id matches, a description exists,
# and kind is rule or procedure (missing means procedure). A rule body (the
# text after the frontmatter, trimmed) stays short because every session loads it.
_check_habit() {
  local fid fdesc fkind fbody len
  IFS=$'\037' read -r _ _ _ fid _ fdesc _ _ _ _ fkind fbody < <(_frontmatter_rows "$2")
  [ "$fid" = "$1" ] || { echo "Frontmatter id '${fid:-missing}' does not match $1" >&2; return 1; }
  [ -n "$fdesc" ] || { echo "Missing frontmatter description for $1" >&2; return 1; }
  case "$fkind" in
    ''|procedure) return 0 ;;
    rule) ;;
    *) echo "Invalid kind '$fkind' for $1: use rule or procedure" >&2; return 1 ;;
  esac
  len=$(printf '%s' "$fbody" | jq -Rs 'gsub("\u001d"; "\n") | gsub("^\\s+|\\s+$"; "") | length')
  [ "$len" -le "$RULE_BODY_MAX" ] || {
    echo "Rule $1 body is $len characters; a rule body must be at most $RULE_BODY_MAX. Shorten it or make it kind: procedure." >&2
    return 1
  }
}

# write-habit <scope> <id> [content]: validate a hidden temp file in the target
# dir, then rename it into place. A dir created for a rejected write is removed.
cmd_write_habit() {
  local scope="${1:-}" id="${2:-}" content dir fresh="" tmp
  _valid_id "$id"
  content="${3:-$(cat)}"
  case "$scope" in
    global) dir="$GLOBAL_DIR" ;;
    project) dir=$(project_dir) || dir="$(project_new_root)/.claude/habits" ;;
    *) echo "Unknown scope: $scope" >&2; exit 1 ;;
  esac
  [ -d "$dir" ] || fresh=1
  mkdir -p "$dir"
  tmp=$(mktemp "$dir/.$id.md.XXXXXX")
  if ! { printf '%s\n' "$content" > "$tmp" && _check_habit "$id" "$tmp" && mv "$tmp" "$dir/$id.md"; }; then
    rm -f "$tmp"
    if [ -n "$fresh" ]; then rmdir "$dir" "${dir%/*}" 2>/dev/null || true; fi
    exit 1
  fi
  echo "OK wrote $dir/$id.md"
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
