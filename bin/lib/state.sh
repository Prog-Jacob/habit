# state.sh: Atomic JSON state read/write.

read_state() {
  require_jq
  local dir="$1"
  if [ -f "$dir/$STATE_FILE" ]; then
    cat "$dir/$STATE_FILE"
  else
    echo "$DEFAULT_STATE"
  fi
}

atomic_write_file() {
  local target="$1"
  local tmp
  tmp=$(mktemp)
  cat > "$tmp"
  mv "$tmp" "$target"
}

write_state() {
  atomic_write_file "$1/$STATE_FILE"
}

# Read state, pipe through a transform, write back.
# NOTE: not atomic across concurrent callers; acceptable for threshold-based counters.
# Usage: update_state "$dir" jq [flags...] 'expression'
update_state() {
  local dir="$1"; shift
  read_state "$dir" | "$@" | write_state "$dir"
}
