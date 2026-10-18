# migrate.sh: v2 to v3 data migration and the history.jsonl backfill.
# Reads settings.local.json files but never modifies them. .v3 is written last.

_migrate_lock() {
  local lock="$GLOBAL_DIR/migrate.lock"
  mkdir -p "$GLOBAL_DIR"
  mkdir "$lock" 2>/dev/null && return 0
  [ -n "$(find "$lock" -maxdepth 0 -mmin +10 2>/dev/null)" ] || return 1
  rm -rf "$lock"
  mkdir "$lock" 2>/dev/null
}

_migrate_unlock() { rmdir "$GLOBAL_DIR/migrate.lock" 2>/dev/null || true; }

_migrate_learnings() {
  local state="$GLOBAL_DIR/settings.local.json" lines
  [ -f "$state" ] || return 0
  # A retry after a failed run must not copy them twice.
  grep -q '"id":"[0-9]*-m[0-9]*"' "$GLOBAL_DIR/learnings.jsonl" 2>/dev/null && return 0
  lines=$(jq -c --arg e "$(date +%s)" '
    (.learnings // []) | to_entries[] | .key as $k | .value
    | select(type == "object" and (.target // "") != "" and (.note // "") != "")
    | {id: "\($e)-m\($k)", ts: (.created // (now | todate)), target, note, origin: (.origin // "")}' \
    "$state" 2>/dev/null) || return 0
  [ -z "$lines" ] || printf '%s\n' "$lines" >> "$GLOBAL_DIR/learnings.jsonl"
}

# Convert one v2 state file's log into log months, tagged with <project>.
_migrate_log() {
  local state="$1/settings.local.json" lines
  [ -f "$state" ] || return 0
  lines=$(jq -r --arg p "$2" '
    (.log // [])[] | select(type == "object" and (.id // "") != "" and (.timestamp | type) == "string")
    | .timestamp[0:7] + "\t" + ({ts: .timestamp, id, project: $p, sid: "", note: (.override // "")} | tojson)' \
    "$state" 2>/dev/null) || return 0
  printf '%s\n' "$lines" | log_append_months
}

# One "seed" log line per valid habit of <scope> from frontmatter last_executed.
_migrate_seed() {
  local scope="$1" proot="$2" pdir=""
  [ -n "$proot" ] && pdir="$proot/.claude/habits"
  _index_rows "$pdir" | jq -rR --arg s "$scope" --arg p "$proot" '
    split("\u001f") | select(.[0] == $s and .[3] != "" and .[3] == .[2] and .[5] != "")
    | select(.[9] | test("^[0-9]{4}-[0-9]{2}"))
    | .[9][0:7] + "\t" + ({ts: .[9], id: .[3], project: $p, sid: "", note: "seed"} | tojson)' \
    | log_append_months
}

_migrate_project() {
  _migrate_log "$1/.claude/habits" "$1" \
    && _migrate_seed project "$1" \
    && echo "$1" >> "$GLOBAL_DIR/migrated-projects"
}

# Steps chained with && so a failure never reaches the .v3 commit marker.
_migrate_all() {
  local proot="" dirs=("$GLOBAL_DIR")
  if proot=$(project_root); then dirs+=("$proot/.claude/habits"); else proot=""; fi
  snapshot_create "$(new_run_id migrate-)" "${dirs[@]}" \
    && _migrate_learnings \
    && _migrate_log "$GLOBAL_DIR" "" \
    && _migrate_seed global "" \
    && { [ -z "$proot" ] || _migrate_project "$proot"; } \
    && echo 3 > "$GLOBAL_DIR/.v3"
}

# A project with a v2 state file not yet in migrated-projects.
_migrate_project_pending() {
  local root
  root=$(project_root) || return 1
  [ -f "$root/.claude/habits/settings.local.json" ] || return 1
  ! grep -qxF "$root" "$GLOBAL_DIR/migrated-projects" 2>/dev/null && echo "$root"
}

# migrate_if_needed [bg]: full migration when .v3 is missing, else migrate the
# current project's v2 log on first touch. Returns 0 silently when locked.
migrate_if_needed() {
  local root did=""
  if [ -f "$GLOBAL_DIR/.v3" ]; then
    root=$(_migrate_project_pending) || return 0
    _migrate_lock || return 0
    if _migrate_project_pending >/dev/null; then _migrate_project "$root" || true; fi
    _migrate_unlock
    return 0
  fi
  _migrate_lock || return 0
  if [ ! -f "$GLOBAL_DIR/.v3" ]; then
    _migrate_all || true
    [ -f "$GLOBAL_DIR/.v3" ] && did=1
  fi
  _migrate_unlock
  [ -n "$did" ] || return 0
  if [ "${1:-}" = "bg" ]; then
    ( migrate_backfill ) </dev/null >/dev/null 2>&1 &
  else
    migrate_backfill
  fi
}

# Last 30 days of ~/.claude/history.jsonl into inbox/claude-backfill-NN.jsonl
# files of at most INBOX_CAP lines, with the capture filter and redaction.
# Leaves backfill-skipped when absent.
migrate_backfill() {
  local hist="$HOME/.claude/history.jsonl"
  if [ ! -f "$hist" ] || ! tail -n 1 "$hist" | jq -e \
      'type == "object" and (.display | type) == "string" and (.timestamp | type) == "number"' >/dev/null 2>&1; then
    : > "$GLOBAL_DIR/backfill-skipped"
    return 0
  fi
  umask 077
  mkdir -p "$GLOBAL_DIR/inbox"
  jq -ncR "$CAPTURE_JQ_DEFS"'
    (now - 2592000) as $since
    | reduce (inputs | fromjson? | select(type == "object" and (.display | type) == "string"
        and (.timestamp | type) == "number" and .timestamp / 1000 >= $since)) as $h
      ({seen: {}, out: []};
       (($h.sessionId // "" | tostring) + "\u0000" + $h.display) as $k
       | if .seen[$k] then . else .seen[$k] = true | .out += [$h] end)
    | .out[] | (.display | strip_cmds) as $p | select(($p | words) >= 3)
    | {ts: (.timestamp / 1000 | floor | todate), host: "claude", sid: (.sessionId // ""),
       cwd: (.project // ""), prompt: ($p | redact)} | fit' "$hist" \
    | awk -v d="$GLOBAL_DIR/inbox" -v cap="$INBOX_CAP" \
        '{ print >> sprintf("%s/claude-backfill-%02d.jsonl", d, int((NR - 1) / cap)) }'
}

cmd_migrate() {
  migrate_if_needed inline
  if [ -f "$GLOBAL_DIR/.v3" ]; then echo "OK v3"; else echo "Migration is running elsewhere; try again"; fi
}
