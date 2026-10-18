# context.sh: Instruction files the user already keeps, so distill can skip
# candidates they already state. Read only.

CONTEXT_FILE_CAP=4000

# Claude Code's project dir name: the root path with every character that is
# not a letter or digit replaced by "-" (per character, not per byte).
_memory_slug() { jq -rn --arg p "$1" '$p | gsub("[^A-Za-z0-9]"; "-")'; }

# context-files [project-root]: each existing file headed ---FILE:<path>---,
# capped at CONTEXT_FILE_CAP characters. The root defaults to the resolved
# project, else the git toplevel or the current directory.
cmd_context_files() {
  local root="${1:-}" f
  if [ -z "$root" ]; then root=$(project_root) || root=$(project_new_root); fi
  root=$(cd "$root" 2>/dev/null && pwd -P) || root="${root%/}"
  for f in "$HOME/.claude/CLAUDE.md" "$root/CLAUDE.md" "$root/AGENTS.md" \
      "$HOME/.claude/projects/$(_memory_slug "$root")/memory/MEMORY.md"; do
    if [ ! -f "$f" ] || [ ! -r "$f" ]; then continue; fi
    printf -- '---FILE:%s---\n' "$f"
    jq -Rrs --argjson cap "$CONTEXT_FILE_CAP" \
      'if length > $cap then .[0:$cap] + "\n[truncated at \($cap) characters]" else sub("\n$"; "") end' "$f"
  done
}
