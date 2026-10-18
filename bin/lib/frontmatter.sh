# frontmatter.sh: YAML frontmatter parsing for write-habit validation.

# Single-pass parse: sets fm_id, fm_tags, fm_description, fm_scope,
# fm_created, fm_updated, fm_archived, fm_last_executed, fm_kind as shell variables.
parse_frontmatter() {
  local file="$1"
  fm_id="" fm_tags="" fm_description="" fm_scope=""
  fm_created="" fm_updated="" fm_archived="" fm_last_executed="" fm_kind=""
  local in_front=0
  while IFS= read -r line; do
    if [ "$line" = "---" ]; then
      in_front=$((in_front + 1))
      [ "$in_front" -ge 2 ] && break
      continue
    fi
    [ "$in_front" -ne 1 ] && continue
    local key="${line%%:*}"
    local val="${line#*:}"
    val="${val#"${val%%[! ]*}"}"
    case "$key" in
      id) fm_id="$val" ;;
      tags) fm_tags="$val" ;;
      description) fm_description="$val" ;;
      scope) fm_scope="$val" ;;
      created) fm_created="$val" ;;
      updated) fm_updated="$val" ;;
      archived) fm_archived="$val" ;;
      last_executed) fm_last_executed="$val" ;;
      kind) fm_kind="$val" ;;
    esac
  done < "$file"
}
