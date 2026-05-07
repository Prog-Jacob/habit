#!/bin/bash
# Test suite for staged changes: multi-read, batch log-exec, active index,
# require_jq hoisting, should-pending removal, _update_frontmatter_timestamp.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$SCRIPT_DIR/bin/habit-tools.sh"
PASS=0
FAIL=0
TESTS=()

cleanup() {
  rm -rf "$TEST_GLOBAL" "$TEST_PROJECT"
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    TESTS+=("PASS: $label")
  else
    FAIL=$((FAIL + 1))
    TESTS+=("FAIL: $label")
    echo "  expected: $(echo "$expected" | head -3)"
    echo "  actual:   $(echo "$actual" | head -3)"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    PASS=$((PASS + 1))
    TESTS+=("PASS: $label")
  else
    FAIL=$((FAIL + 1))
    TESTS+=("FAIL: $label")
    echo "  expected to contain: $needle"
    echo "  actual: $(echo "$haystack" | head -3)"
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF -- "$needle" 2>/dev/null; then
    FAIL=$((FAIL + 1))
    TESTS+=("FAIL: $label")
    echo "  should not contain: $needle"
  else
    PASS=$((PASS + 1))
    TESTS+=("PASS: $label")
  fi
}

assert_exit_code() {
  local label="$1" expected="$2"
  shift 2
  local actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  if [ "$expected" -eq "$actual" ]; then
    PASS=$((PASS + 1))
    TESTS+=("PASS: $label")
  else
    FAIL=$((FAIL + 1))
    TESTS+=("FAIL: $label")
    echo "  expected exit code: $expected, got: $actual"
  fi
}

# --- Setup ---
TEST_GLOBAL=$(mktemp -d)
TEST_PROJECT=$(mktemp -d)
trap cleanup EXIT

# Override paths by setting env. habit-tools uses common.sh constants,
# so we need to intercept. We'll source the libs directly for unit tests
# and use the full CLI for integration tests.
export HOME_OVERRIDE="$TEST_GLOBAL"

# Create habit files in global
mkdir -p "$TEST_GLOBAL"
cat > "$TEST_GLOBAL/cleanup-writing.md" << 'HABIT'
---
id: cleanup-writing
tags: [writing, quality]
description: Replace em dashes with natural punctuation.
scope: global
created: 2026-04-11T13:00:00Z
updated: 2026-05-07T00:00:00Z
archived: false
---

## Instruction

Fix dashes.
HABIT

cat > "$TEST_GLOBAL/old-habit.md" << 'HABIT'
---
id: old-habit
tags: [deprecated]
description: An archived habit.
scope: global
created: 2026-01-01T00:00:00Z
updated: 2026-01-01T00:00:00Z
archived: true
---

## Instruction

Deprecated.
HABIT

cat > "$TEST_GLOBAL/smart-tests.md" << 'HABIT'
---
id: smart-tests
tags: [testing, quality]
description: Write focused tests.
scope: global
created: 2026-05-04T00:00:00Z
updated: 2026-05-07T00:00:00Z
archived: false
last_executed: 2026-05-07T01:40:36Z
---

## Instruction

Test well.
HABIT

# Create a state file with index entries
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

# Create project state
mkdir -p "$TEST_PROJECT"
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

cat > "$TEST_PROJECT/project-habit.md" << 'HABIT'
---
id: project-habit
tags: [project]
description: Project only.
scope: project
created: 2026-05-07T00:00:00Z
updated: 2026-05-07T00:00:00Z
archived: false
---

## Instruction

Project specific.
HABIT

# --- Unit tests: source libs directly with overridden paths ---
echo "=== Unit Tests ==="

# Source common and state
source "$SCRIPT_DIR/bin/lib/common.sh"
source "$SCRIPT_DIR/bin/lib/state.sh"
source "$SCRIPT_DIR/bin/lib/frontmatter.sh"

# Override dirs
GLOBAL_DIR="$TEST_GLOBAL"
PROJECT_DIR="$TEST_PROJECT"

source "$SCRIPT_DIR/bin/lib/habit.sh"

# Test 1: _resolve_habit finds global habit
result=$(_resolve_habit "cleanup-writing")
assert_eq "_resolve_habit global" "global $TEST_GLOBAL/cleanup-writing.md" "$result"

# Test 2: _resolve_habit finds project habit
result=$(_resolve_habit "project-habit")
assert_eq "_resolve_habit project" "project $TEST_PROJECT/project-habit.md" "$result"

# Test 3: _resolve_habit returns 1 for missing
exit_code=0
_resolve_habit "nonexistent" >/dev/null 2>&1 || exit_code=$?
assert_eq "_resolve_habit missing returns 1" "1" "$exit_code"

# Test 4: _resolve_habit trims trailing text
result=$(_resolve_habit "cleanup-writing extra text")
assert_eq "_resolve_habit trims" "global $TEST_GLOBAL/cleanup-writing.md" "$result"

# Test 5: _update_frontmatter_timestamp updates existing timestamp
cp "$TEST_GLOBAL/smart-tests.md" "$TEST_GLOBAL/smart-tests.md.bak"
_update_frontmatter_timestamp "$TEST_GLOBAL/smart-tests.md" "2026-06-01T00:00:00Z"
result=$(grep "^last_executed:" "$TEST_GLOBAL/smart-tests.md")
assert_eq "_update_frontmatter_timestamp updates" "last_executed: 2026-06-01T00:00:00Z" "$result"
cp "$TEST_GLOBAL/smart-tests.md.bak" "$TEST_GLOBAL/smart-tests.md"

# Test 6: _update_frontmatter_timestamp adds to file without one
cat > "$TEST_GLOBAL/no-ts.md" << 'HABIT'
---
id: no-ts
tags: [test]
description: No timestamp.
scope: global
created: 2026-01-01T00:00:00Z
updated: 2026-01-01T00:00:00Z
archived: false
---

## Instruction

No ts.
HABIT
_update_frontmatter_timestamp "$TEST_GLOBAL/no-ts.md" "2026-06-01T12:00:00Z"
result=$(grep "^last_executed:" "$TEST_GLOBAL/no-ts.md")
assert_eq "_update_frontmatter_timestamp inserts" "last_executed: 2026-06-01T12:00:00Z" "$result"
rm "$TEST_GLOBAL/no-ts.md"

# Test 7: _update_frontmatter_timestamp no-op on missing file
exit_code=0
_update_frontmatter_timestamp "/tmp/nonexistent_habit_file.md" "2026-01-01T00:00:00Z" || exit_code=$?
assert_eq "_update_frontmatter_timestamp missing file returns 0" "0" "$exit_code"

# Test 8: cmd_read_habit single ID
result=$(cmd_read_habit "cleanup-writing")
assert_contains "read_habit single has SCOPE" "SCOPE:global" "$result"
assert_contains "read_habit single has content" "Fix dashes." "$result"

# Test 9: cmd_read_habit multiple IDs
result=$(cmd_read_habit "cleanup-writing" "smart-tests")
assert_contains "read_habit multi delim 1" "---HABIT:cleanup-writing---" "$result"
assert_contains "read_habit multi delim 2" "---HABIT:smart-tests---" "$result"
assert_contains "read_habit multi scope 1" "SCOPE:global" "$result"
assert_contains "read_habit multi content" "Fix dashes." "$result"
assert_contains "read_habit multi content 2" "Test well." "$result"

# Test 10: cmd_read_habit multi with missing
result=$(cmd_read_habit "cleanup-writing" "nonexistent")
assert_contains "read_habit multi missing shows NOT_FOUND" "NOT_FOUND" "$result"
assert_contains "read_habit multi missing shows found" "---HABIT:cleanup-writing---" "$result"

# Test 11: cmd_read_habit no args
result=$(cmd_read_habit 2>/dev/null || true)
assert_contains "read_habit no args" "NOT_FOUND" "$result"

# Test 12: cmd_read_index active mode
result=$(cmd_read_index merged active)
assert_not_contains "read_index active excludes archived" "old-habit" "$result"
assert_contains "read_index active includes active" "cleanup-writing" "$result"
assert_contains "read_index active includes active 2" "smart-tests" "$result"
# Verify compact format: should have id, tags, description, scope but not created/updated/archived
result_entry=$(echo "$result" | jq -c '.entries[0] | keys | sort')
expected_keys='["description","id","scope","tags"]'
assert_eq "read_index active compact keys" "$expected_keys" "$result_entry"

# Test 13: cmd_read_index merged (no filter)
result=$(cmd_read_index merged)
assert_contains "read_index merged includes archived" "old-habit" "$result"
assert_contains "read_index merged includes active" "cleanup-writing" "$result"

# Test 14: cmd_read_index with project scope
result=$(cmd_read_index project)
assert_contains "read_index project" "project-habit" "$result"
assert_not_contains "read_index project no global" "cleanup-writing" "$result"

# Test 15: cmd_log_exec single mode returns OK
result=$(cmd_log_exec global cleanup-writing "test execution")
assert_eq "log_exec single returns OK" "OK" "$result"

# Test 16: cmd_log_exec single mode updates index
result=$(cat "$TEST_GLOBAL/settings.local.json" | jq -r '.index[] | select(.id=="cleanup-writing") | .last_executed')
assert_not_contains "log_exec single updates last_executed" "null" "$result"

# Test 17: cmd_log_exec single mode appends to log
result=$(cat "$TEST_GLOBAL/settings.local.json" | jq '.log | length')
assert_eq "log_exec single appends log" "1" "$result"

# Test 18: cmd_log_exec single mode updates frontmatter
result=$(grep "^last_executed:" "$TEST_GLOBAL/cleanup-writing.md")
assert_contains "log_exec single updates frontmatter" "last_executed:" "$result"

# Test 19: cmd_log_exec batch mode
result=$(cmd_log_exec '[{"scope":"global","id":"smart-tests","override":"batch test"},{"scope":"project","id":"project-habit","override":"batch project test"}]')
assert_contains "log_exec batch returns OK logged" "OK logged 2" "$result"

# Test 20: batch mode updates global index
result=$(cat "$TEST_GLOBAL/settings.local.json" | jq -r '.index[] | select(.id=="smart-tests") | .last_executed')
assert_not_contains "batch updates global index" "null" "$result"

# Test 21: batch mode updates project index
result=$(cat "$TEST_PROJECT/settings.local.json" | jq -r '.index[] | select(.id=="project-habit") | .last_executed')
assert_not_contains "batch updates project index" "null" "$result"

# Test 22: batch mode appends to global log
result=$(cat "$TEST_GLOBAL/settings.local.json" | jq '[.log[] | select(.id=="smart-tests")] | length')
assert_eq "batch appends global log" "1" "$result"

# Test 23: batch mode appends to project log
result=$(cat "$TEST_PROJECT/settings.local.json" | jq '[.log[] | select(.id=="project-habit")] | length')
assert_eq "batch appends project log" "1" "$result"

# Test 24: batch mode updates frontmatter in global
result=$(grep "^last_executed:" "$TEST_GLOBAL/smart-tests.md")
assert_contains "batch updates global frontmatter" "last_executed:" "$result"

# Test 25: batch mode updates frontmatter in project
result=$(grep "^last_executed:" "$TEST_PROJECT/project-habit.md")
assert_contains "batch updates project frontmatter" "last_executed:" "$result"

# Test 26: batch with no overrides (just timestamps)
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
result=$(cmd_log_exec '[{"scope":"global","id":"cleanup-writing","override":""}]')
assert_contains "batch no override returns OK" "OK logged 1" "$result"
log_len=$(cat "$TEST_GLOBAL/settings.local.json" | jq '.log | length')
assert_eq "batch no override skips log" "0" "$log_len"

# Test 27: should-pending command is removed
echo ""
echo "=== Integration Tests ==="
result=$(bash "$TOOLS" should-pending 2>&1 || true)
assert_contains "should-pending removed" "Usage:" "$result"

# Test 28: read-index active via CLI
result=$(GLOBAL_DIR="$TEST_GLOBAL" PROJECT_DIR="$TEST_PROJECT" bash -c "
  source '$SCRIPT_DIR/bin/lib/common.sh'
  source '$SCRIPT_DIR/bin/lib/state.sh'
  source '$SCRIPT_DIR/bin/lib/frontmatter.sh'
  GLOBAL_DIR='$TEST_GLOBAL'
  PROJECT_DIR='$TEST_PROJECT'
  source '$SCRIPT_DIR/bin/lib/habit.sh'
  cmd_read_index merged active
")
assert_not_contains "CLI read-index active excludes archived" "old-habit" "$result"

# Test 29: _extract_user_messages format
source "$SCRIPT_DIR/bin/lib/query.sh"

TRANSCRIPT=$(mktemp)
cat > "$TRANSCRIPT" << 'JSONL'
{"type":"user","timestamp":"2026-05-07T14:30:00.000Z","message":{"content":"Hello world"}}
{"type":"user","timestamp":"2026-05-07T14:31:00.000Z","message":{"content":"Run /habit:suggest"}}
{"type":"assistant","timestamp":"2026-05-07T14:31:01.000Z","message":{"content":"Sure"}}
{"type":"user","timestamp":"2026-05-07T14:32:00.000Z","message":{"content":"Fix the bug"}}
JSONL

result=$(_extract_user_messages "$TRANSCRIPT")
assert_contains "transcript has numbering" "[1 |" "$result"
assert_contains "transcript has timestamp" "14:30" "$result"
assert_contains "transcript tags plugin messages" "plugin" "$result"
assert_contains "transcript has content" "Hello world" "$result"
assert_contains "transcript skips assistant" "Fix the bug" "$result"
assert_not_contains "transcript excludes assistant content" "Sure" "$result"
rm "$TRANSCRIPT"

# Test 30: _extract_user_messages filters system noise
TRANSCRIPT=$(mktemp)
cat > "$TRANSCRIPT" << 'JSONL'
{"type":"user","timestamp":"2026-05-07T14:30:00.000Z","message":{"content":"<local-command-caveat>stuff</local-command-caveat>"}}
{"type":"user","timestamp":"2026-05-07T14:31:00.000Z","message":{"content":"Real message"}}
{"type":"user","timestamp":"2026-05-07T14:32:00.000Z","message":{"content":"<command-name>foo</command-name>"}}
{"type":"user","timestamp":"2026-05-07T14:33:00.000Z","message":{"content":"Base directory for this skill: /foo/bar"}}
JSONL

result=$(_extract_user_messages "$TRANSCRIPT")
assert_contains "transcript keeps real messages" "Real message" "$result"
assert_not_contains "transcript filters local-command" "local-command-caveat" "$result"
assert_not_contains "transcript filters command-name" "command-name" "$result"
assert_not_contains "transcript filters base directory" "Base directory" "$result"
rm "$TRANSCRIPT"

# Test 31: _extract_user_messages handles array content
TRANSCRIPT=$(mktemp)
cat > "$TRANSCRIPT" << 'JSONL'
{"type":"user","timestamp":"2026-05-07T14:30:00.000Z","message":{"content":[{"type":"text","text":"Array message"},{"type":"image","data":"..."}]}}
JSONL

result=$(_extract_user_messages "$TRANSCRIPT")
assert_contains "transcript handles array content" "Array message" "$result"
rm "$TRANSCRIPT"

# Test 32: _extract_user_messages handles missing timestamp
TRANSCRIPT=$(mktemp)
cat > "$TRANSCRIPT" << 'JSONL'
{"type":"user","message":{"content":"No timestamp"}}
JSONL

result=$(_extract_user_messages "$TRANSCRIPT")
assert_contains "transcript handles missing timestamp" "??:??" "$result"
rm "$TRANSCRIPT"

# --- Summary ---
echo ""
echo "=== Results ==="
for t in "${TESTS[@]}"; do
  echo "  $t"
done
echo ""
echo "Total: $((PASS + FAIL)) | Pass: $PASS | Fail: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
