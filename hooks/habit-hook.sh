#!/bin/bash
# Habit hook dispatcher. Routes lifecycle events to habit-tools.sh.
# Usage: habit-hook.sh <command> <jq-field> [jq-field...]
# Reads hook input from stdin, extracts named fields via jq, calls the command.
# Always exits 0 (hooks must never block).

INPUT=$(cat)
CMD="$1"; shift

ARGS=()
for field in "$@"; do
  ARGS+=("$(echo "$INPUT" | jq -r ".$field // \"\"")")
done

[ -z "${ARGS[0]:-}" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
bash "$SCRIPT_DIR/bin/habit-tools.sh" "$CMD" "${ARGS[@]}"

exit 0
