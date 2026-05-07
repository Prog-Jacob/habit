# observation.sh: Plugin self-improvement observation log.

cmd_log_observation() {
  local session_id="${1:-}"
  local signal="${2:-}"
  [ -z "$signal" ] && { echo "Error: signal required" >&2; exit 1; }
  ensure_dir "$GLOBAL_DIR"

  update_state "$GLOBAL_DIR" jq \
    --arg ts "$(now_utc)" --arg sig "$signal" --arg sid "$session_id" \
    '.observations = ((.observations // []) + [{timestamp: $ts, signal: $sig, session_id: $sid}])'

  echo "OK observation logged"
}

cmd_read_observations() {
  read_state "$GLOBAL_DIR" | jq -r '
    (.observations // []) | if length == 0 then "No observations."
    else to_entries[] | "\(.key + 1). [\(.value.timestamp)] \(.value.signal)" end'
}

cmd_clear_observations() {
  update_state "$GLOBAL_DIR" jq '.observations = []'
  echo "OK observations cleared"
}
