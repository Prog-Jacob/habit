# Shared helpers and fixtures for the habit bats suite.
# Dependency-free: relies only on bats core (run/$status/$output) plus the two
# substring assertions below, which mirror the suite's dominant grep -qF idiom.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
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

# Source the library layer with GLOBAL_DIR/PROJECT_DIR pointed at scratch dirs.
# common.sh seeds those from $HOME at source time, so we override afterwards.
source_libs() {
  source "$REPO_ROOT/bin/lib/common.sh"
  source "$REPO_ROOT/bin/lib/state.sh"
  source "$REPO_ROOT/bin/lib/frontmatter.sh"
  GLOBAL_DIR="$TEST_GLOBAL"
  PROJECT_DIR="$TEST_PROJECT"
  source "$REPO_ROOT/bin/lib/habit.sh"
}

# Write the canonical fixture set: three global habits (one archived), a global
# index over them, and a single project habit with its own state.
seed_fixtures() {
  TEST_GLOBAL="$(mktemp -d)"
  TEST_PROJECT="$(mktemp -d)"

  _write_habit "$TEST_GLOBAL/cleanup-writing.md" cleanup-writing \
    "[writing, quality]" "Replace em dashes with natural punctuation." global false "Fix dashes."
  _write_habit "$TEST_GLOBAL/old-habit.md" old-habit \
    "[deprecated]" "An archived habit." global true "Deprecated."
  _write_habit "$TEST_GLOBAL/smart-tests.md" smart-tests \
    "[testing, quality]" "Write focused tests." global false "Test well."

  cat > "$TEST_GLOBAL/settings.local.json" << 'JSON'
{
  "index": [
    {"id": "cleanup-writing", "tags": ["writing","quality"], "description": "Replace em dashes.", "scope": "global", "archived": false},
    {"id": "old-habit", "tags": ["deprecated"], "description": "Archived.", "scope": "global", "archived": true},
    {"id": "smart-tests", "tags": ["testing","quality"], "description": "Write focused tests.", "scope": "global", "archived": false}
  ],
  "meta": {"update_counter": 5, "last_deep_timestamp": null},
  "log": [],
  "sessions": {},
  "observations": []
}
JSON

  _write_habit "$TEST_PROJECT/project-habit.md" project-habit \
    "[project]" "Project only." project false "Project specific."
  cat > "$TEST_PROJECT/settings.local.json" << 'JSON'
{
  "index": [
    {"id": "project-habit", "tags": ["project"], "description": "Project only.", "scope": "project", "archived": false}
  ],
  "meta": {"update_counter": 0, "last_deep_timestamp": null},
  "log": [],
  "sessions": {},
  "observations": []
}
JSON
}

teardown_fixtures() {
  rm -rf "$TEST_GLOBAL" "$TEST_PROJECT"
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

# Slugify a workspace path the way the tools do (leading slash stripped,
# remaining slashes to dashes).
slugify() { echo "${1#/}" | tr '/' '-'; }
