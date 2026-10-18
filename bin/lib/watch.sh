# watch.sh: The watch CLI: status, the global capture pause, the distill
# notice snooze, and forgetting a learning. paused holds the pause expiry epoch.

# Local "YYYY-MM-DD HH:MM" for an epoch (BSD date, then GNU date).
_local_time() {
  date -r "$1" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$1" '+%Y-%m-%d %H:%M'
}

# The capture pause expiry epoch, while it is in the future.
_paused_until() {
  local until
  until=$(cat "$GLOBAL_DIR/paused" 2>/dev/null) || return 1
  case "$until" in ''|*[!0-9]*) return 1 ;; esac
  [ "$until" -gt "$(date +%s)" ] && echo "$until"
}

# _watch_count <value> <max>: print the value as a decimal in 1..max, or fail.
_watch_count() {
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  [ "${#1}" -le 6 ] || return 1
  local n=$((10#$1))
  [ "$n" -gt 0 ] && [ "$n" -le "$2" ] && echo "$n"
}

_watch_off() {
  local hours until tmp
  hours=$(_watch_count "${1:-8}" 8760) || { echo "Usage: watch off [hours]" >&2; exit 1; }
  until=$(( $(date +%s) + hours * 3600 ))
  mkdir -p "$GLOBAL_DIR"
  tmp=$(mktemp "$GLOBAL_DIR/.paused.XXXXXX")
  if echo "$until" > "$tmp" && mv "$tmp" "$GLOBAL_DIR/paused"; then
    echo "PAUSED until $(_local_time "$until")"
  else
    rm -f "$tmp"; exit 1
  fi
}

# snooze [days]: no distill reminder for <days> (7 when none are given).
_watch_snooze() {
  local days next
  days=$(_watch_count "${1:-7}" 365) || { echo "Usage: watch snooze [days]" >&2; exit 1; }
  next=$(nudge_set_next $((days * 86400))) || exit 1
  echo "Distill reminders snoozed until $(_local_time "$next")"
}

cmd_watch() {
  case "${1:-status}" in
    status) cmd_status ;;
    off) _watch_off "${2:-}" ;;
    on) rm -f "$GLOBAL_DIR/paused"; echo "ACTIVE" ;;
    snooze) _watch_snooze "${2:-}" ;;
    forget) cmd_forget_learning "${2:-}" ;;
    *) echo "Usage: watch [status | off [hours] | on | snooze [days] | forget <n>]" >&2; exit 1 ;;
  esac
}
