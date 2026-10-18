# usage-log.sh: Append-only usage log in log/YYYY-MM.jsonl.

# Concatenate every month file (nothing when none).
log_lines() {
  local files=() f
  for f in "$GLOBAL_DIR"/log/*.jsonl; do [ -f "$f" ] && files+=("$f"); done
  if [ ${#files[@]} -gt 0 ]; then cat "${files[@]}"; fi
}

# Append "<YYYY-MM>\t<json>" lines from stdin, one printf per line.
log_append_months() {
  local month line
  mkdir -p "$GLOBAL_DIR/log" || return 1
  while IFS=$'\t' read -r month line; do
    [ -n "$line" ] || continue
    printf '%s\n' "$line" >> "$GLOBAL_DIR/log/$month.jsonl" || return 1
  done
  return 0
}

# log-exec '<json array of {scope, id, note?}>' [sid]
cmd_log_exec() {
  local entries="${1:-}" sid="${2:-}" proot="" lines
  printf '%s' "$entries" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || { echo "Usage: log-exec '<json array of {scope, id, note}>' [sid]" >&2; exit 1; }
  if printf '%s' "$entries" | jq -e 'any(.[]; .scope == "project")' >/dev/null; then
    proot=$(project_root) || proot=$(project_new_root)
  fi
  lines=$(printf '%s' "$entries" | jq -r --arg sid "$sid" --arg proot "$proot" '
    (now | todate) as $ts
    | .[] | select((.id // "") != "")
    | ($ts[0:7]) + "\t" + ({ts: $ts, id, project: (if .scope == "project" then $proot else "" end),
        sid: $sid, note: (.note // "")} | tojson)')
  printf '%s\n' "$lines" | log_append_months
  echo "OK logged $(printf '%s' "$entries" | jq 'length')"
}

cmd_read_log() {
  log_lines | jq -cR 'fromjson? | select(type == "object")'
}
