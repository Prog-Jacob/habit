# frontmatter.sh: YAML frontmatter parsing and index entry building.

# Single-pass parse: sets fm_id, fm_tags, fm_description, fm_scope,
# fm_created, fm_updated, fm_archived, fm_last_executed as shell variables.
parse_frontmatter() {
  local file="$1"
  fm_id="" fm_tags="" fm_description="" fm_scope=""
  fm_created="" fm_updated="" fm_archived="" fm_last_executed=""
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
    esac
  done < "$file"
}

# Build a JSON index entry from a habit .md file.
build_index_entry() {
  local file="$1"
  parse_frontmatter "$file"

  local raw_tags="${fm_tags#[}"
  raw_tags="${raw_tags%]}"

  local archived_val="false"
  [ "$fm_archived" = "true" ] && archived_val="true"

  # Strip surrounding quotes from description if present.
  local desc="${fm_description#\"}"
  desc="${desc%\"}"

  jq -n \
    --arg id "$fm_id" \
    --arg rawtags "$raw_tags" \
    --arg description "$desc" \
    --arg scope "$fm_scope" \
    --arg created "$fm_created" \
    --arg updated "$fm_updated" \
    --argjson archived "$archived_val" \
    --arg last_executed "$fm_last_executed" \
    '{id: $id,
      tags: ($rawtags | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))),
      description: $description, scope: $scope, created: $created, updated: $updated, archived: $archived}
     | if $last_executed != "" then .last_executed = $last_executed else . end'
}
