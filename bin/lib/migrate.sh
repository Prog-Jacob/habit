# migrate.sh: v2 to v3 migration (learnings) and the history.jsonl backfill.
# Reads settings.local.json but never modifies it.

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

# .v3 is written last, so a failed learnings copy is retried on the next call.
# Habit files need no conversion: the index falls back to their frontmatter
# last_executed, and the v2 log held no signal worth keeping (B14).
_migrate_all() {
  _migrate_learnings && echo 3 > "$GLOBAL_DIR/.v3"
}

# migrate_if_needed [bg]: migrate once when .v3 is missing, then backfill.
# Returns 0 silently when another process holds the lock.
migrate_if_needed() {
  local did=""
  [ -f "$GLOBAL_DIR/.v3" ] && return 0
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
# Skipped when the file is absent or its last line has another shape.
migrate_backfill() {
  local hist="$HOME/.claude/history.jsonl"
  [ -f "$hist" ] && tail -n 1 "$hist" | jq -e \
    'type == "object" and (.display | type) == "string" and (.timestamp | type) == "number"' >/dev/null 2>&1 \
    || return 0
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
