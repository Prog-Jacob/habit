# project.sh: Project scope resolution. Project dirs hold only habit files.

# Physical path of $1, or of its nearest existing ancestor.
_existing_dir() {
  local p="$1"
  while [ -n "$p" ]; do
    (cd "$p" 2>/dev/null && pwd -P) && return 0
    [ "$p" = "/" ] && return 1
    p=$(dirname "$p")
  done
  return 1
}

# Nearest ancestor of [start] holding .claude/habits, stopping before $HOME.
# Prints nothing and returns 1 when none. Never creates dirs.
project_root() {
  local d home global
  d=$(_existing_dir "${1:-${HABIT_PROJECT_DIR:-$(pwd -P)}}") || return 1
  home=$(cd "$HOME" 2>/dev/null && pwd -P) || home="$HOME"
  while [ "$d" != "$home" ]; do
    if [ -d "$d/.claude/habits" ]; then
      global=$(cd "$GLOBAL_DIR" 2>/dev/null && pwd -P) || global=""
      [ "$(cd "$d/.claude/habits" && pwd -P)" = "$global" ] && return 1
      echo "$d"; return 0
    fi
    [ "$d" = "/" ] && return 1
    d=$(dirname "$d")
  done
  return 1
}

# Habits dir of the resolved project, or return 1.
project_dir() {
  local root
  root=$(project_root "$@") || return 1
  echo "$root/.claude/habits"
}

# Root a new project scope would use: HABIT_PROJECT_DIR, the git toplevel, or pwd.
project_new_root() {
  if [ -n "${HABIT_PROJECT_DIR:-}" ]; then
    echo "$HABIT_PROJECT_DIR"
  else
    git rev-parse --show-toplevel 2>/dev/null || pwd -P
  fi
}
