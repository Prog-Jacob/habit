# watch.sh: Global capture pause and status. paused holds the expiry epoch.

# Local "YYYY-MM-DD HH:MM" for an epoch (BSD date, then GNU date).
_local_time() {
  date -r "$1" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$1" '+%Y-%m-%d %H:%M'
}

_watch_status() {
  local until now n=0 f newest
  now=$(date +%s)
  until=$(cat "$GLOBAL_DIR/paused" 2>/dev/null) || until=""
  case "$until" in ''|*[!0-9]*) until=0 ;; esac
  if [ "$until" -gt "$now" ]; then echo "PAUSED until $(_local_time "$until")"; else echo "ACTIVE"; fi
  while IFS= read -r f; do n=$((n + $(wc -l < "$f"))); done < <(inbox_files)
  echo "Inbox: $n prompts waiting for distill"
  newest=$(for f in "$GLOBAL_DIR"/inbox/*.jsonl "$GLOBAL_DIR"/inbox/.claimed/*/*.jsonl "$GLOBAL_DIR"/inbox/.done/*/*.jsonl; do
    if [ -f "$f" ]; then tail -n 1 "$f"; fi
  done | jq -nR '[inputs | fromjson? | .ts? // empty | strings | fromdateiso8601? // empty] | max // empty')
  if [ -n "$newest" ]; then echo "Last capture: $(_local_time "$newest")"; else echo "Last capture: none"; fi
}

cmd_watch() {
  local hours until tmp
  case "${1:-status}" in
    off)
      hours="${2:-8}"
      case "$hours" in ''|*[!0-9]*) echo "Usage: watch off [hours]" >&2; exit 1 ;; esac
      hours=$((10#$hours))
      [ "$hours" -gt 0 ] || { echo "Usage: watch off [hours]" >&2; exit 1; }
      until=$(( $(date +%s) + hours * 3600 ))
      mkdir -p "$GLOBAL_DIR"
      tmp=$(mktemp "$GLOBAL_DIR/.paused.XXXXXX")
      if echo "$until" > "$tmp" && mv "$tmp" "$GLOBAL_DIR/paused"; then
        echo "PAUSED until $(_local_time "$until")"
      else
        rm -f "$tmp"; exit 1
      fi
      ;;
    on) rm -f "$GLOBAL_DIR/paused"; echo "ACTIVE" ;;
    status) _watch_status ;;
    *) echo "Usage: watch [status | off [hours] | on]" >&2; exit 1 ;;
  esac
}
