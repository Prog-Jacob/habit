# frontmatter.sh: YAML frontmatter parsing and index entry building.

# Single-pass parse: sets fm_id, fm_tags, fm_description, fm_scope,
# fm_created, fm_updated, fm_archived, fm_last_executed as shell variables.
parse_frontmatter() {
  local file="$1"
  fm_id="" fm_tags="" fm_description="" fm_scope=""
  fm_created="" fm_updated="" fm_archived="" fm_last_executed=""
  eval "$(awk '
    /^---$/ { block++; next }
    block == 1 {
      key = $0; sub(/: .*/, "", key)
      val = $0; sub(/^[^:]+: */, "", val)
      if (key ~ /^(id|tags|description|scope|created|updated|archived|last_executed)$/) {
        gsub(/'\''/, "'\''\\'\'''\''", val)
        print "fm_" key "='\''" val "'\''"
      }
    }
    block >= 2 { exit }
  ' "$file")"
}

# Build a JSON index entry from a habit .md file.
build_index_entry() {
  require_jq
  local file="$1"
  parse_frontmatter "$file"

  # Strip brackets from tags field: "[tag1, tag2]" -> "tag1, tag2"
  local raw_tags="${fm_tags#[}"
  raw_tags="${raw_tags%]}"

  local tags_json="[]"
  if [ -n "$raw_tags" ]; then
    tags_json=$(echo "$raw_tags" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | jq -R . | jq -s .)
  fi

  local archived_val="false"
  [ "$fm_archived" = "true" ] && archived_val="true"

  # Strip surrounding quotes from description if present.
  local desc="${fm_description#\"}"
  desc="${desc%\"}"

  jq -n \
    --arg id "$fm_id" \
    --argjson tags "$tags_json" \
    --arg description "$desc" \
    --arg scope "$fm_scope" \
    --arg created "$fm_created" \
    --arg updated "$fm_updated" \
    --argjson archived "$archived_val" \
    --arg last_executed "$fm_last_executed" \
    '{id: $id, tags: $tags, description: $description, scope: $scope, created: $created, updated: $updated, archived: $archived}
     | if $last_executed != "" then .last_executed = $last_executed else . end'
}
