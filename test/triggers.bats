#!/usr/bin/env bats
# Trigger semantics: which conditions surface "Habit maintenance available",
# and the prune-log bound that Regular distill relies on. The isolated HOME
# keeps cmd_check_triggers from scanning the developer's real machine state.

load test_helper

# Run cmd_check_triggers against scratch state dirs with a clean HOME.
# Usage: check_triggers <global_state_json> <project_state_json> <session_id>
check_triggers() {
  local g="$BATS_TEST_TMPDIR/ct-global"
  local p="$BATS_TEST_TMPDIR/ct-project"
  local h="$BATS_TEST_TMPDIR/ct-home"
  mkdir -p "$g" "$p" "$h"
  printf '%s' "$1" > "$g/settings.local.json"
  printf '%s' "$2" > "$p/settings.local.json"
  run bash -c "
    HOME='$h' GLOBAL_DIR='$g' PROJECT_DIR='$p'
    source '$REPO_ROOT/bin/lib/common.sh'
    source '$REPO_ROOT/bin/lib/state.sh'
    GLOBAL_DIR='$g'; PROJECT_DIR='$p'
    source '$REPO_ROOT/bin/lib/query.sh'
    cmd_check_triggers '$3'
  "
}

@test "a high update counter and a long log alone do not fire" {
  local long_log
  long_log=$(jq -n '[range(60) | {ts:"x",scope:"global",id:"h"}]')
  local g
  g=$(jq -n --argjson l "$long_log" '{index:[],meta:{update_counter:99,pending_sessions:[],distilled_project_sessions:{}},log:$l,sessions:{},observations:[],learnings:[]}')
  check_triggers "$g" '{"index":[],"meta":{"update_counter":99,"pending_sessions":[],"distilled_project_sessions":{}},"log":[],"sessions":{},"observations":[],"learnings":[]}' ''
  [ -z "$output" ]
}

@test "a prompt count crossing the threshold fires" {
  check_triggers \
    '{"index":[],"meta":{"update_counter":0,"pending_sessions":[],"distilled_project_sessions":{}},"log":[],"sessions":{"s1":{"prompt_count":20}},"observations":[],"learnings":[]}' \
    '{"index":[],"meta":{"update_counter":0,"pending_sessions":[],"distilled_project_sessions":{}},"log":[],"sessions":{},"observations":[],"learnings":[]}' \
    s1
  assert_contains "Habit maintenance available" "$output"
}

@test "a session below the prompt threshold does not fire" {
  check_triggers \
    '{"index":[],"meta":{"update_counter":0,"pending_sessions":[],"distilled_project_sessions":{}},"log":[],"sessions":{"s1":{"prompt_count":19}},"observations":[],"learnings":[]}' \
    '{"index":[],"meta":{"update_counter":0,"pending_sessions":[],"distilled_project_sessions":{}},"log":[],"sessions":{},"observations":[],"learnings":[]}' \
    s1
  [ -z "$output" ]
}

@test "a pending session fires" {
  check_triggers \
    '{"index":[],"meta":{"update_counter":0,"pending_sessions":[{"transcript_path":"/x.jsonl"}],"distilled_project_sessions":{}},"log":[],"sessions":{},"observations":[],"learnings":[]}' \
    '{"index":[],"meta":{"update_counter":0,"pending_sessions":[],"distilled_project_sessions":{}},"log":[],"sessions":{},"observations":[],"learnings":[]}' \
    ''
  assert_contains "Habit maintenance available" "$output"
}

@test "a new undistilled project session fires on its own" {
  local home="$BATS_TEST_TMPDIR/ct4"
  mkdir -p "$home/.claude/habits"
  echo '{"index":[],"meta":{"update_counter":0,"pending_sessions":[],"distilled_project_sessions":{}},"log":[],"sessions":{},"observations":[],"learnings":[]}' > "$home/.claude/habits/settings.local.json"
  local ws="$home/work"
  mkdir -p "$ws"
  local cur="$home/.cursor/projects/$(slugify "$ws")/agent-transcripts/zzz999"
  mkdir -p "$cur"
  echo '{"role":"user","message":{"content":[{"type":"text","text":"<user_query>new work</user_query>"}]}}' > "$cur/zzz999.jsonl"
  run bash -c "cd '$ws' && HOME='$home' bash '$TOOLS' check-triggers nosession"
  assert_contains "Habit maintenance available" "$output"
}

@test "prune-log bounds the log to LOG_RETAIN" {
  local d="$BATS_TEST_TMPDIR/pl"
  mkdir -p "$d"
  jq -n '[range(60) | {ts:"x",scope:"global",id:"h"}]' \
    | jq '{index:[],meta:{},log:.,sessions:{},observations:[],learnings:[]}' > "$d/settings.local.json"
  bash -c "
    source '$REPO_ROOT/bin/lib/common.sh'
    source '$REPO_ROOT/bin/lib/state.sh'
    GLOBAL_DIR='$d'
    source '$REPO_ROOT/bin/lib/maintenance.sh'
    cmd_prune_log global
  " >/dev/null
  [ "$(jq '.log | length' "$d/settings.local.json")" -eq 25 ]
}
