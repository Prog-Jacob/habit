# index.sh: Habit index derived from the *.md frontmatter on every read.

# One awk pass over <file>... One \037-joined row per file: scope path stem id
# tags description created updated archived last_executed kind body, where body
# is kept for rules only, its lines joined by \035.
_frontmatter_rows() {
  awk -v g="$GLOBAL_DIR/" '
    function emit(  s, stem) {
      if (file == "") return
      s = (index(file, g) == 1) ? "global" : "project"
      stem = file; sub(/.*\//, "", stem); sub(/\.md$/, "", stem)
      print s "\037" file "\037" stem "\037" v["id"] "\037" v["tags"] "\037" v["description"] "\037" \
        v["created"] "\037" v["updated"] "\037" v["archived"] "\037" v["last_executed"] "\037" v["kind"] "\037" body
    }
    FNR == 1 { emit(); file = FILENAME; n = 0; body = ""; split("", v) }
    { sub(/\r$/, "") }
    n >= 2 { if (v["kind"] == "rule") body = body $0 "\035"; next }
    $0 == "---" { n++; next }
    n == 1 { k = $0; sub(/:.*/, "", k); val = $0; sub(/^[^:]*:/, "", val); sub(/^ +/, "", val); v[k] = val }
    END { emit() }
  ' "$@"
}

# Rows for the global habit files and those in [project habits dir].
_index_rows() {
  local pdir="${1:-}" f files=()
  for f in "$GLOBAL_DIR"/*.md; do [ -f "$f" ] && files+=("$f"); done
  if [ -n "$pdir" ]; then
    for f in "$pdir"/*.md; do [ -f "$f" ] && files+=("$f"); done
  fi
  [ ${#files[@]} -eq 0 ] || _frontmatter_rows "${files[@]}"
}

INDEX_JQ_DEFS='
def rows: $rows | split("\n")[] | select(length > 0) | split("\u001f")
  | {scope: .[0], path: .[1], stem: .[2], id: .[3], tags: .[4], description: .[5],
     created: .[6], updated: .[7], archived: .[8], le: .[9], kind: .[10], body: (.[11] // "")};
def valid: .id != "" and .id == .stem and .description != "";
'

# Print the index as {entries:[...]}. Project entries shadow global ones;
# last_executed comes from the usage log, falling back to frontmatter.
cmd_read_index() {
  local scope="${1:-merged}" mode="${2:-}" proot="" pdir=""
  case "$scope" in project|merged) ;; *) echo "Unknown scope: $scope" >&2; exit 1 ;; esac
  if proot=$(project_root); then pdir="$proot/.claude/habits"; else proot=""; fi
  log_lines | jq -nR --rawfile rows <(_index_rows "$pdir") \
    --arg scope "$scope" --arg mode "$mode" --arg proot "$proot" "$INDEX_JQ_DEFS"'
    ([inputs | fromjson? | select(type == "object" and (.id | type) == "string" and (.ts | type) == "string")]
     | reduce .[] as $l ({}; ($l.id + "\t" + ($l.project // "")) as $k
         | if (.[$k] // "") < $l.ts then .[$k] = $l.ts else . end)) as $last
    | [rows | select(valid) | . as $r
       | ($last[$r.id + "\t" + (if $r.scope == "project" then $proot else "" end)] // $r.le) as $le
       | {id, tags: (.tags | ltrimstr("[") | rtrimstr("]") | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))),
          description: (.description | ltrimstr("\"") | rtrimstr("\"")), scope, created, updated,
          archived: (.archived == "true")}
       + (if $le != "" then {last_executed: $le} else {} end)
       + (if $r.kind != "" then {kind: $r.kind} else {} end)] as $all
    | ($all | map(select(.scope == "project"))) as $p
    | (if $scope == "project" then $p
       else ($p | map(.id)) as $pids
         | $p + ($all | map(select(.scope == "global" and (.id as $i | any($pids[]; . == $i) | not))))
       end)
    | sort_by(.id)
    | if $mode == "active" then map(select(.archived != true) | {id, tags, description, scope} + (if .kind then {kind} else {} end)) else . end
    | {entries: .}'
}

# List habit files the index skips, with the reason.
cmd_invalid_habits() {
  local pdir=""
  pdir=$(project_dir) || pdir=""
  jq -nr --rawfile rows <(_index_rows "$pdir") "$INDEX_JQ_DEFS"'
    rows | select(valid | not)
    | "\(.path): " + (if .id == "" then "missing id"
        elif .id != .stem then "id \(.id) does not match the filename"
        else "missing description" end)'
}
