#!/bin/bash
# habit-tools.sh: CLI for Habit file operations.
# All intelligence (classification, interpretation, dedup) is done by the model.
# This script only handles mechanical file I/O. Each command is a cmd_* function.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null  # the Makefile lints lib/*.sh on their own
for lib in "$SCRIPT_DIR"/lib/*.sh; do source "$lib"; done

cmd="${1:-}"; shift || true
if ! declare -F "cmd_${cmd//-/_}" >/dev/null; then
  echo "Usage: habit-tools.sh <command> [args]" >&2
  echo "Commands: $(declare -F | sed -n 's/^declare -f cmd_//p' | tr '_\n' '- ')" >&2
  exit 1
fi
# session-start runs without jq so it can write the shim and say jq is missing.
[ "$cmd" = session-start ] || require_jq

# Hooks migrate on their own; status only observes and reports a missing .v3.
case "$cmd" in
  capture|session-start|pre-compact|status|migrate|env-context) ;;
  *) migrate_if_needed inline >/dev/null 2>&1 || true ;;
esac

"cmd_${cmd//-/_}" "$@"
