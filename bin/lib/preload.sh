# preload.sh: One call that prints what a skill reads first, in delimited
# sections. Each section runs in a subshell: a failing read prints its error
# in the section body and the rest still prints.

_section() { # _section <name> <command...>
  printf '===%s===\n' "$1"
  shift
  ( "$@" ) 2>&1 || true
  printf '\n'
}

_shared_doc() { cat "$SCRIPT_DIR/../skills/habit-shared/$1"; }

_recent_log() { cmd_read_log | tail -n 200; }

cmd_preload() {
  case "${1:-}" in
    habit|suggest)
      _section LEARNINGS cmd_read_learnings "$1"
      _section INDEX cmd_read_index merged active
      ;;
    edit)
      _section LEARNINGS cmd_read_learnings edit
      _section PROCESSING _shared_doc PROCESSING.md
      ;;
    watch) ( cmd_watch status ) 2>&1 || true ;;
    distill)
      _section LEARNINGS cmd_read_learnings distill
      _section INDEX cmd_read_index merged
      _section LOG _recent_log
      _section PROCESSING _shared_doc PROCESSING.md
      _section OPERATIONS _shared_doc OPERATIONS.md
      ;;
    *) echo "Usage: preload <habit|suggest|edit|watch|distill>" >&2; exit 1 ;;
  esac
}
