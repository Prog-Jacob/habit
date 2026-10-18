#!/usr/bin/env bats
# Library unit tests: read-habit, read-index, log-exec, write-habit,
# and delete-habit. Each test gets a fresh fixture set, so the suite
# never leans on mutation order between cases.

load test_helper

setup() {
  seed_fixtures
  source_libs
}

teardown() {
  teardown_fixtures
}

@test "cmd_read_habit lowercases ids, drops override words, finds project habits, and rejects paths" {
  printf 'outside\n' > "$TEST_PROJECT/../escape.md"
  run cmd_read_habit "Project-Habit only in auth" ../escape
  [ "${lines[0]}" = "---HABIT:Project-Habit---" ]
  [ "${lines[1]}" = "SCOPE:project" ]
  assert_contains "$(printf -- '---HABIT:../escape---\nNOT_FOUND')" "$output"
  refute_contains "outside" "$output"
}

@test "cmd_read_habit emits SCOPE and the file for a single id, with no header" {
  run cmd_read_habit cleanup-writing
  [ "$output" = "$(printf 'SCOPE:global\n%s' "$(cat "$TEST_GLOBAL/cleanup-writing.md")")" ]
}

@test "cmd_read_habit reports NOT_FOUND between found ids" {
  run cmd_read_habit cleanup-writing nonexistent smart-tests
  [ "$output" = "$(printf -- '---HABIT:cleanup-writing---\nSCOPE:global\n%s\n---HABIT:nonexistent---\nNOT_FOUND\n---HABIT:smart-tests---\nSCOPE:global\n%s' \
    "$(cat "$TEST_GLOBAL/cleanup-writing.md")" "$(cat "$TEST_GLOBAL/smart-tests.md")")" ]
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

@test "cmd_log_exec appends one log line and leaves the habit file alone" {
  cp "$TEST_GLOBAL/cleanup-writing.md" "$BATS_TEST_TMPDIR/md"
  run cmd_log_exec '[{"scope":"global","id":"cleanup-writing","note":"test execution"}]'
  [ "$output" = "OK logged 1" ]
  run cmd_read_log
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(echo "$output" | jq -r '[.id, .project, .note] | join("|")')" = "cleanup-writing||test execution" ]
  cmp "$TEST_GLOBAL/cleanup-writing.md" "$BATS_TEST_TMPDIR/md"
}

@test "cmd_log_exec rejects anything but a JSON array and logs nothing" {
  run cmd_log_exec global cleanup-writing
  [ "$status" -ne 0 ]
  assert_contains "Usage: log-exec" "$output"
  [ -z "$(cmd_read_log)" ]
}

@test "cmd_log_exec batch mode logs global and project entries with the project path and sid" {
  run cmd_log_exec '[{"scope":"global","id":"smart-tests","note":"batch test"},{"scope":"project","id":"project-habit","note":"batch project test"}]' sid-9
  assert_contains "OK logged 2" "$output"
  run cmd_read_log
  [ "$(echo "$output" | jq -r 'select(.id=="smart-tests") | [.project, .sid, .note] | join("|")')" = "|sid-9|batch test" ]
  [ "$(echo "$output" | jq -r 'select(.id=="project-habit") | [.project, .sid, .note] | join("|")')" = "$TEST_PROJECT_ROOT|sid-9|batch project test" ]
  [ ! -d "$TEST_PROJECT/log" ]
}

@test "cmd_log_exec with no note logs an empty note" {
  run cmd_log_exec '[{"scope":"global","id":"cleanup-writing"}]'
  assert_contains "OK logged 1" "$output"
  [ "$(cmd_read_log | jq -r '.note')" = "" ]
}

@test "cmd_write_habit writes the file and the derived index picks it up" {
  run cmd_write_habit global new-habit "$(cat << 'MD'
---
id: new-habit
tags: [alpha, beta]
description: A freshly written habit.
scope: global
created: 2026-06-01T00:00:00Z
updated: 2026-06-01T00:00:00Z
archived: false
---

## Instruction

Do the thing.
MD
)"
  assert_contains "OK wrote" "$output"

  run cmd_read_habit new-habit
  assert_contains "SCOPE:global" "$output"
  assert_contains "Do the thing." "$output"

  local entry
  entry=$(cmd_read_index merged | jq -c '.entries[] | select(.id=="new-habit")')
  assert_contains '"description":"A freshly written habit."' "$entry"
  assert_contains '"alpha"' "$entry"
  assert_contains '"beta"' "$entry"
  assert_contains '"archived":false' "$entry"
}

@test "cmd_write_habit rejects an invalid id or an unknown scope" {
  run cmd_write_habit global "Bad ID" "anything"
  [ "$status" -ne 0 ]
  assert_contains "Invalid id" "$output"
  run cmd_write_habit elsewhere fine-id "$(printf -- '---\nid: fine-id\ndescription: Fine.\n---\n')"
  [ "$status" -ne 0 ]
  assert_contains "Unknown scope: elsewhere" "$output"
  [ ! -e "$TEST_GLOBAL/fine-id.md" ]
}

@test "cmd_write_habit rejects a frontmatter id mismatch and writes nothing" {
  run cmd_write_habit global mismatched-id "$(cat << 'MD'
---
id: other-id
tags: [x]
description: Something.
scope: global
archived: false
---

## Instruction

Body.
MD
)"
  [ "$status" -ne 0 ]
  assert_contains "does not match" "$output"
  [ ! -f "$TEST_GLOBAL/mismatched-id.md" ]
}

@test "cmd_write_habit rejects a missing description" {
  run cmd_write_habit global no-desc "$(cat << 'MD'
---
id: no-desc
tags: [x]
scope: global
archived: false
---

## Instruction

Body.
MD
)"
  [ "$status" -ne 0 ]
  assert_contains "Missing frontmatter description" "$output"
  [ ! -f "$TEST_GLOBAL/no-desc.md" ]
}

@test "cmd_delete_habit removes a global or project habit file" {
  run cmd_delete_habit global smart-tests
  assert_contains "OK deleted $TEST_GLOBAL/smart-tests.md" "$output"
  [ ! -f "$TEST_GLOBAL/smart-tests.md" ]
  run cmd_delete_habit project project-habit
  assert_contains "OK deleted" "$output"
  [ ! -f "$TEST_PROJECT/project-habit.md" ]
  [ -d "$TEST_PROJECT" ]
}

@test "cmd_delete_habit rejects a bad id, a bad scope, and a missing habit" {
  run cmd_delete_habit global "../etc"
  [ "$status" -ne 0 ]
  assert_contains "Invalid id" "$output"
  run cmd_delete_habit elsewhere smart-tests
  [ "$status" -ne 0 ]
  run cmd_delete_habit global nonexistent
  [ "$status" -ne 0 ]
  [ -f "$TEST_GLOBAL/smart-tests.md" ]
}

@test "delete-habit project scope with no project dir fails and creates nothing" {
  local h
  h=$(new_home del)
  mkdir -p "$h/repo"
  run bash -c "cd '$h/repo' && HOME='$h' HABIT_PROJECT_DIR='$h/repo' bash '$TOOLS' delete-habit project some-id"
  [ "$status" -ne 0 ]
  [ ! -e "$h/repo/.claude" ]
}
