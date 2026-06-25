#!/usr/bin/env bats
# Library unit tests: resolve, frontmatter, read-habit, read-index, log-exec,
# and transcript extraction. Each test gets a fresh fixture set, so the suite
# never leans on mutation order between cases.

load test_helper

setup() {
  seed_fixtures
  source_libs
}

teardown() {
  teardown_fixtures
}

@test "_resolve_habit finds a global habit" {
  run _resolve_habit cleanup-writing
  [ "$status" -eq 0 ]
  [ "$output" = "global $TEST_GLOBAL/cleanup-writing.md" ]
}

@test "_resolve_habit finds a project habit" {
  run _resolve_habit project-habit
  [ "$status" -eq 0 ]
  [ "$output" = "project $TEST_PROJECT/project-habit.md" ]
}

@test "_resolve_habit returns 1 for a missing habit" {
  run _resolve_habit nonexistent
  [ "$status" -eq 1 ]
}

@test "_resolve_habit trims trailing text after the id" {
  run _resolve_habit "cleanup-writing extra text"
  [ "$output" = "global $TEST_GLOBAL/cleanup-writing.md" ]
}

@test "_update_frontmatter_timestamp updates an existing timestamp" {
  printf '\nlast_executed: 2026-01-01T00:00:00Z\n' >> "$TEST_GLOBAL/smart-tests.md"
  _update_frontmatter_timestamp "$TEST_GLOBAL/smart-tests.md" "2026-06-01T00:00:00Z"
  run grep "^last_executed:" "$TEST_GLOBAL/smart-tests.md"
  [ "$output" = "last_executed: 2026-06-01T00:00:00Z" ]
}

@test "_update_frontmatter_timestamp inserts when none is present" {
  _update_frontmatter_timestamp "$TEST_GLOBAL/cleanup-writing.md" "2026-06-01T12:00:00Z"
  run grep "^last_executed:" "$TEST_GLOBAL/cleanup-writing.md"
  [ "$output" = "last_executed: 2026-06-01T12:00:00Z" ]
}

@test "_update_frontmatter_timestamp is a no-op on a missing file" {
  run _update_frontmatter_timestamp "/tmp/nonexistent_habit_file.md" "2026-01-01T00:00:00Z"
  [ "$status" -eq 0 ]
}

@test "cmd_read_habit emits SCOPE and body for a single id" {
  run cmd_read_habit cleanup-writing
  assert_contains "SCOPE:global" "$output"
  assert_contains "Fix dashes." "$output"
}

@test "cmd_read_habit delimits and emits each of multiple ids" {
  run cmd_read_habit cleanup-writing smart-tests
  assert_contains "---HABIT:cleanup-writing---" "$output"
  assert_contains "---HABIT:smart-tests---" "$output"
  assert_contains "SCOPE:global" "$output"
  assert_contains "Fix dashes." "$output"
  assert_contains "Test well." "$output"
}

@test "cmd_read_habit reports NOT_FOUND alongside found ids" {
  run cmd_read_habit cleanup-writing nonexistent
  assert_contains "NOT_FOUND" "$output"
  assert_contains "---HABIT:cleanup-writing---" "$output"
}

@test "cmd_read_habit with no args reports NOT_FOUND" {
  run cmd_read_habit
  assert_contains "NOT_FOUND" "$output"
}

@test "cmd_read_index active mode excludes archived and stays compact" {
  run cmd_read_index merged active
  refute_contains "old-habit" "$output"
  assert_contains "cleanup-writing" "$output"
  assert_contains "smart-tests" "$output"
  local keys
  keys=$(echo "$output" | jq -c '.entries[0] | keys | sort')
  [ "$keys" = '["description","id","scope","tags"]' ]
}

@test "cmd_read_index merged includes archived" {
  run cmd_read_index merged
  assert_contains "old-habit" "$output"
  assert_contains "cleanup-writing" "$output"
}

@test "cmd_read_index project scope excludes global" {
  run cmd_read_index project
  assert_contains "project-habit" "$output"
  refute_contains "cleanup-writing" "$output"
}

@test "cmd_log_exec single mode returns OK" {
  run cmd_log_exec global cleanup-writing "test execution"
  [ "$output" = "OK" ]
}

@test "cmd_log_exec single mode stamps the index, log, and frontmatter" {
  cmd_log_exec global cleanup-writing "test execution"
  local ts log_len
  ts=$(jq -r '.index[] | select(.id=="cleanup-writing") | .last_executed' "$TEST_GLOBAL/settings.local.json")
  refute_contains "null" "$ts"
  log_len=$(jq '.log | length' "$TEST_GLOBAL/settings.local.json")
  [ "$log_len" -eq 1 ]
  run grep "^last_executed:" "$TEST_GLOBAL/cleanup-writing.md"
  assert_contains "last_executed:" "$output"
}

@test "cmd_log_exec batch mode logs across global and project" {
  run cmd_log_exec '[{"scope":"global","id":"smart-tests","override":"batch test"},{"scope":"project","id":"project-habit","override":"batch project test"}]'
  assert_contains "OK logged 2" "$output"

  refute_contains "null" "$(jq -r '.index[] | select(.id=="smart-tests") | .last_executed' "$TEST_GLOBAL/settings.local.json")"
  refute_contains "null" "$(jq -r '.index[] | select(.id=="project-habit") | .last_executed' "$TEST_PROJECT/settings.local.json")"
  [ "$(jq '[.log[] | select(.id=="smart-tests")] | length' "$TEST_GLOBAL/settings.local.json")" -eq 1 ]
  [ "$(jq '[.log[] | select(.id=="project-habit")] | length' "$TEST_PROJECT/settings.local.json")" -eq 1 ]
  run grep "^last_executed:" "$TEST_GLOBAL/smart-tests.md"
  assert_contains "last_executed:" "$output"
  run grep "^last_executed:" "$TEST_PROJECT/project-habit.md"
  assert_contains "last_executed:" "$output"
}

@test "cmd_log_exec batch with an empty override stamps without logging" {
  run cmd_log_exec '[{"scope":"global","id":"cleanup-writing","override":""}]'
  assert_contains "OK logged 1" "$output"
  [ "$(jq '.log | length' "$TEST_GLOBAL/settings.local.json")" -eq 0 ]
}

@test "_extract_user_messages numbers, timestamps, and tags plugin prompts" {
  source "$REPO_ROOT/bin/lib/query.sh"
  local t
  t=$(mktemp)
  cat > "$t" << 'JSONL'
{"type":"user","timestamp":"2026-05-07T14:30:00.000Z","message":{"content":"Hello world"}}
{"type":"user","timestamp":"2026-05-07T14:31:00.000Z","message":{"content":"Run /habit:suggest"}}
{"type":"assistant","timestamp":"2026-05-07T14:31:01.000Z","message":{"content":"Sure"}}
{"type":"user","timestamp":"2026-05-07T14:32:00.000Z","message":{"content":"Fix the bug"}}
JSONL
  run _extract_user_messages "$t"
  rm "$t"
  assert_contains "[1 |" "$output"
  assert_contains "14:30" "$output"
  assert_contains "plugin" "$output"
  assert_contains "Hello world" "$output"
  assert_contains "Fix the bug" "$output"
  refute_contains "Sure" "$output"
}

@test "_extract_user_messages filters system noise" {
  source "$REPO_ROOT/bin/lib/query.sh"
  local t
  t=$(mktemp)
  cat > "$t" << 'JSONL'
{"type":"user","timestamp":"2026-05-07T14:30:00.000Z","message":{"content":"<local-command-caveat>stuff</local-command-caveat>"}}
{"type":"user","timestamp":"2026-05-07T14:31:00.000Z","message":{"content":"Real message"}}
{"type":"user","timestamp":"2026-05-07T14:32:00.000Z","message":{"content":"<command-name>foo</command-name>"}}
{"type":"user","timestamp":"2026-05-07T14:33:00.000Z","message":{"content":"Base directory for this skill: /foo/bar"}}
JSONL
  run _extract_user_messages "$t"
  rm "$t"
  assert_contains "Real message" "$output"
  refute_contains "local-command-caveat" "$output"
  refute_contains "command-name" "$output"
  refute_contains "Base directory" "$output"
}

@test "_extract_user_messages handles array content" {
  source "$REPO_ROOT/bin/lib/query.sh"
  local t
  t=$(mktemp)
  echo '{"type":"user","timestamp":"2026-05-07T14:30:00.000Z","message":{"content":[{"type":"text","text":"Array message"},{"type":"image","data":"..."}]}}' > "$t"
  run _extract_user_messages "$t"
  rm "$t"
  assert_contains "Array message" "$output"
}

@test "_extract_user_messages handles a missing timestamp" {
  source "$REPO_ROOT/bin/lib/query.sh"
  local t
  t=$(mktemp)
  echo '{"type":"user","message":{"content":"No timestamp"}}' > "$t"
  run _extract_user_messages "$t"
  rm "$t"
  assert_contains "??:??" "$output"
}

@test "_extract_user_messages reads the Cursor role format and strips wrappers" {
  source "$REPO_ROOT/bin/lib/query.sh"
  local t
  t=$(mktemp)
  cat > "$t" << 'JSONL'
{"role":"user","message":{"content":[{"type":"text","text":"<timestamp>2026-05-07T14:30:00Z</timestamp>\n<user_query>\nCursor real prompt here\n</user_query>"}]}}
{"role":"assistant","message":{"content":[{"type":"text","text":"Reply"}]}}
{"role":"user","message":{"content":[{"type":"text","text":"<user_query>second cursor prompt</user_query>"}]}}
JSONL
  run _extract_user_messages "$t"
  rm "$t"
  assert_contains "Cursor real prompt here" "$output"
  assert_contains "second cursor prompt" "$output"
  refute_contains "Reply" "$output"
  refute_contains "<timestamp>" "$output"
  refute_contains "user_query" "$output"
}
