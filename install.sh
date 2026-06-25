#!/bin/bash
# Habit fallback installer for Claude Code and Cursor.
# Real installs use the plugin marketplaces. This manual path links the repo into
# each tool that is present, keeping bin/ and skills/ siblings so read-shared works.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
DID=0

link() { mkdir -p "$(dirname "$2")"; rm -rf "$2"; ln -s "$1" "$2"; echo "linked $2 -> $1"; }

# Link the whole repo under each tool's skills root as a single "habit" dir,
# preserving the sibling bin/ + skills/ layout that read-shared depends on.
install_into() { # <tool_skills_dir>
  link "$ROOT" "$1/habit-plugin"
  echo "  skills available under $1/habit-plugin/skills/"
}

if [ -d "$HOME/.claude" ]; then
  install_into "$HOME/.claude/skills"
  echo "Claude Code: linked. The marketplace install also wires hooks; for this manual"
  echo "path, add hooks/hooks.json entries to your Claude Code settings if you want capture."
  DID=1
fi

if [ -d "$HOME/.cursor" ]; then
  install_into "$HOME/.cursor/skills"
  link "$ROOT/hooks/habit-hook.sh" "$HOME/.cursor/hooks/habit-hook.sh"
  echo "Cursor: linked. Merge hooks/hooks.cursor.json into ~/.cursor/hooks.json to enable capture."
  DID=1
fi

chmod +x "$ROOT/bin/habit-tools.sh" "$ROOT/hooks/habit-hook.sh" 2>/dev/null || true
[ "$DID" -eq 0 ] && { echo "No ~/.claude or ~/.cursor found." >&2; exit 1; }
echo "Done."
