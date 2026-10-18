# Shared helpers and fixtures for the habit bats suite.
# Dependency-free: relies only on bats core (run/$status/$output) plus the two
# substring assertions below, which mirror the suite's dominant grep -qF idiom.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
TOOLS="$REPO_ROOT/bin/habit-tools.sh"
HOOK="$REPO_ROOT/hooks/habit-hook.sh"

# Substring assertions over an arbitrary string (not just $output).
assert_contains() {
  if [[ "$2" != *"$1"* ]]; then
    printf 'expected to contain: %s\n            actual: %s\n' "$1" "${2:0:200}" >&2
    return 1
  fi
}

refute_contains() {
  if [[ "$2" == *"$1"* ]]; then
    printf 'should not contain: %s\n           actual: %s\n' "$1" "${2:0:200}" >&2
    return 1
  fi
}

# Source the library layer with GLOBAL_DIR pointed at a scratch dir. common.sh
# seeds it from $HOME at source time, so we override afterwards. The project
# scope resolves through HABIT_PROJECT_DIR (set by seed_fixtures).
source_libs() {
  source "$REPO_ROOT/bin/lib/common.sh"
  source "$REPO_ROOT/bin/lib/frontmatter.sh"
  GLOBAL_DIR="$TEST_GLOBAL"
  source "$REPO_ROOT/bin/lib/project.sh"
  source "$REPO_ROOT/bin/lib/usage-log.sh"
  source "$REPO_ROOT/bin/lib/index.sh"
  source "$REPO_ROOT/bin/lib/habit.sh"
}

# Write the canonical fixture set: three global habits (one archived) and a
# single project habit.
seed_fixtures() {
  TEST_GLOBAL="$(mktemp -d)"
  TEST_PROJECT_ROOT="$(cd "$(mktemp -d)" && pwd -P)"
  TEST_PROJECT="$TEST_PROJECT_ROOT/.claude/habits"
  mkdir -p "$TEST_PROJECT"
  export HABIT_PROJECT_DIR="$TEST_PROJECT_ROOT"

  _write_habit "$TEST_GLOBAL/cleanup-writing.md" cleanup-writing \
    "[writing, quality]" "Replace em dashes with natural punctuation." global false "Fix dashes."
  _write_habit "$TEST_GLOBAL/old-habit.md" old-habit \
    "[deprecated]" "An archived habit." global true "Deprecated."
  _write_habit "$TEST_GLOBAL/smart-tests.md" smart-tests \
    "[testing, quality]" "Write focused tests." global false "Test well."

  _write_habit "$TEST_PROJECT/project-habit.md" project-habit \
    "[project]" "Project only." project false "Project specific."
}

teardown_fixtures() {
  rm -rf "$TEST_GLOBAL" "$TEST_PROJECT_ROOT"
}

# A scratch HOME with an empty global habits dir. Prints its path.
new_home() {
  local h="$BATS_TEST_TMPDIR/${1:-home}"
  mkdir -p "$h/.claude/habits"
  echo "$h"
}

# Run the CLI with HOME=<home> from <cwd>: hx <home> <cwd> <args...>
hx() {
  local h="$1" cwd="$2"
  shift 2
  (cd "$cwd" && HOME="$h" bash "$TOOLS" "$@")
}

# _write_habit <path> <id> <tags> <description> <scope> <archived> <body>
_write_habit() {
  cat > "$1" << EOF
---
id: $2
tags: $3
description: $4
scope: $5
created: 2026-05-04T00:00:00Z
updated: 2026-05-07T00:00:00Z
archived: $6
---

## Instruction

$7
EOF
}

# seed_inbox <file> <lines> <age days> [projects]: prompt lines stamped <age>
# days ago, with cwd cycling over [projects] distinct dirs. Appends.
seed_inbox() {
  mkdir -p "$(dirname "$1")"
  jq -nc --argjson n "$2" --argjson d "$3" --argjson p "${4:-1}" 'range($n) as $i
    | {ts: (now - $d * 86400 | floor | todate), host: "claude", sid: "s", cwd: "/p\($i % $p)", prompt: "a prompt numbered \($i)"}' >> "$1"
}

# Write a shim at <home> pointing at this checkout, as session-start would.
seed_shim() {
  mkdir -p "$1/.claude/habits/bin"
  printf '#!/bin/bash\n# habit-shim 9.9.9\nexec bash "%s" "$@"\n' "$TOOLS" > "$1/.claude/habits/bin/habit-tools.sh"
}
