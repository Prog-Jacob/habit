#!/usr/bin/env bats
# Integration tests: the CLI and hook dispatcher end to end, breadcrumbs,
# session discovery, install linking, the learnings store, env detection, and
# robustness against malformed/corrupt inputs. Each test works inside the
# per-test $BATS_TEST_TMPDIR, which bats removes automatically.

load test_helper

@test "should-pending is removed (prints usage)" {
  run bash "$TOOLS" should-pending
  assert_contains "Usage:" "$output"
}

@test "list-new-sessions finds a Cursor session with no Claude Code project dir" {
  local home="$BATS_TEST_TMPDIR/lns"
  mkdir -p "$home/.claude/habits"
  local ws="$home/work"
  mkdir -p "$ws"
  local cur="$home/.cursor/projects/$(slugify "$ws")/agent-transcripts/abc123"
  mkdir -p "$cur"
  echo '{"role":"user","message":{"content":[{"type":"text","text":"<user_query>hi there</user_query>"}]}}' > "$cur/abc123.jsonl"
  run bash -c "cd '$ws' && HOME='$home' bash '$TOOLS' list-new-sessions"
  assert_contains "abc123.jsonl" "$output"
  refute_contains "/.." "$output"
}

@test "write_breadcrumb records HABIT_BIN and HABIT_SID" {
  local bc="$BATS_TEST_TMPDIR/bc"
  mkdir -p "$bc"
  bash -c "
    source '$REPO_ROOT/bin/lib/common.sh'
    source '$REPO_ROOT/bin/lib/state.sh'
    GLOBAL_DIR='$bc'
    SCRIPT_DIR='$REPO_ROOT/bin'
    write_breadcrumb 'sess-123'
  "
  run cat "$bc/current"
  assert_contains "HABIT_SID=sess-123" "$output"
  assert_contains "HABIT_BIN=$REPO_ROOT/bin/habit-tools.sh" "$output"
}

@test "clear_breadcrumb removes the breadcrumb file" {
  local bc="$BATS_TEST_TMPDIR/bc2"
  mkdir -p "$bc"
  printf 'HABIT_SID=x\n' > "$bc/current"
  bash -c "source '$REPO_ROOT/bin/lib/common.sh'; GLOBAL_DIR='$bc'; clear_breadcrumb"
  [ ! -f "$bc/current" ]
}

@test "distill-preload emits every section and reads the shared docs" {
  local home="$BATS_TEST_TMPDIR/dp"
  mkdir -p "$home/.claude/habits"
  run bash -c "HOME='$home' bash '$TOOLS' distill-preload ''"
  assert_contains "===TRANSCRIPT===" "$output"
  assert_contains "===OPERATIONS===" "$output"
  assert_contains "Habit Processing Rules" "$output"
  assert_contains "Habit Operations Reference" "$output"
}

@test "hook session-init writes the Claude Code session id from stdin" {
  local home="$BATS_TEST_TMPDIR/hk"
  echo '{"session_id":"cc-1"}' | HOME="$home" bash "$HOOK" session-init >/dev/null 2>&1
  run cat "$home/.claude/habits/current"
  assert_contains "HABIT_SID=cc-1" "$output"
}

@test "hook session-init generates an id when Cursor provides none" {
  local home="$BATS_TEST_TMPDIR/hk2"
  echo '{}' | HOME="$home" bash "$HOOK" session-init >/dev/null 2>&1
  run cat "$home/.claude/habits/current"
  assert_contains "HABIT_SID=cursor-" "$output"
}

@test "hook prompt-tick increments the breadcrumb session count" {
  local home="$BATS_TEST_TMPDIR/hk3"
  echo '{"session_id":"cc-1"}' | HOME="$home" bash "$HOOK" session-init >/dev/null 2>&1
  echo '{"prompt":"this is a prompt with more than five words"}' \
    | HOME="$home" bash "$HOOK" prompt-tick >/dev/null 2>&1
  run bash -c "HOME='$home' bash '$TOOLS' read-prompt-count cc-1"
  [ "$output" = "1" ]
}

@test "hook exits 0 on empty input" {
  local home="$BATS_TEST_TMPDIR/hk4"
  run bash -c "echo '' | HOME='$home' bash '$HOOK' prompt-tick"
  [ "$status" -eq 0 ]
}

@test "install links the repo under a present tool's skills dir" {
  local in="$BATS_TEST_TMPDIR/install"
  mkdir -p "$in/.cursor"
  HOME="$in" bash "$REPO_ROOT/install.sh" >/dev/null 2>&1 || true
  [ -L "$in/.cursor/skills/habit-plugin" ]
  [ -L "$in/.cursor/hooks/habit-hook.sh" ]
  [ -f "$in/.cursor/skills/habit-plugin/skills/habit-shared/PROCESSING.md" ]
}

@test "read-sessions survives a malformed jsonl and still emits good sessions" {
  local home="$BATS_TEST_TMPDIR/rs"
  local ws="$home/proj"
  mkdir -p "$ws"
  local proj="$home/.claude/projects/$(echo "$ws" | tr '/' '-')"
  mkdir -p "$proj"
  printf 'this is not json\n' > "$proj/bad.jsonl"
  echo '{"type":"user","message":{"content":"a valid user prompt with several words here"}}' > "$proj/good.jsonl"
  run bash -c "cd '$ws' && HOME='$home' bash '$TOOLS' read-sessions"
  [ "$status" -eq 0 ]
  assert_contains "valid user prompt" "$output"
}

@test "distill-preload completes all sections even when project state is corrupt" {
  local home="$BATS_TEST_TMPDIR/dpc"
  local ws="$home/proj"
  mkdir -p "$home/.claude/habits" "$ws/.claude/habits"
  printf 'NOT JSON' > "$ws/.claude/habits/settings.local.json"
  run bash -c "cd '$ws' && HOME='$home' bash '$TOOLS' distill-preload ''"
  [ "$status" -eq 0 ]
  assert_contains "===OPERATIONS===" "$output"
}

@test "learnings store round-trips, merges global, and serves empty stores" {
  local home="$BATS_TEST_TMPDIR/lrn"
  mkdir -p "$home/.claude/habits"
  HOME="$home" bash "$TOOLS" write-learning run "scope overrides to the named module" "obs1" >/dev/null
  HOME="$home" bash "$TOOLS" write-learning global "summaries stay short" "obs2" >/dev/null

  run bash -c "HOME='$home' bash '$TOOLS' read-learnings run"
  assert_contains "scope overrides to the named module" "$output"
  assert_contains "summaries stay short" "$output"

  run bash -c "HOME='$home' bash '$TOOLS' read-learnings edit"
  assert_contains "summaries stay short" "$output"

  local empty="$BATS_TEST_TMPDIR/lrn-empty"
  mkdir -p "$empty/.claude/habits"
  run bash -c "HOME='$empty' bash '$TOOLS' read-learnings edit"
  [ -z "$output" ]
}

@test "read-learnings tolerates a state file predating the learnings key" {
  local home="$BATS_TEST_TMPDIR/lrn-old"
  mkdir -p "$home/.claude/habits"
  printf '%s' '{"index":[],"meta":{},"log":[],"sessions":{},"observations":[]}' > "$home/.claude/habits/settings.local.json"
  run bash -c "HOME='$home' bash '$TOOLS' read-learnings run"
  [ -z "$output" ]
}

@test "prune-learnings de-duplicates a repeated target+note" {
  local home="$BATS_TEST_TMPDIR/lrn-dup"
  mkdir -p "$home/.claude/habits"
  HOME="$home" bash "$TOOLS" write-learning run "scope overrides to the named module" "obs1" >/dev/null
  HOME="$home" bash "$TOOLS" write-learning run "scope overrides to the named module" "obs3" >/dev/null
  HOME="$home" bash "$TOOLS" prune-learnings >/dev/null
  local n
  n=$(jq '[.learnings[] | select(.target=="run" and .note=="scope overrides to the named module")] | length' "$home/.claude/habits/settings.local.json")
  [ "$n" -eq 1 ]
}

@test "env-context detects a habit checkout vs an installed copy" {
  local src="$BATS_TEST_TMPDIR/ec-src"
  mkdir -p "$src"
  (cd "$src" && git init -q && git remote add origin https://github.com/Prog-Jacob/habit.git)
  run bash "$TOOLS" env-context "$src"
  [ "$output" = "source" ]

  local inst="$BATS_TEST_TMPDIR/ec-inst"
  mkdir -p "$inst"
  run bash "$TOOLS" env-context "$inst"
  [ "$output" = "installed" ]

  local other="$BATS_TEST_TMPDIR/ec-other"
  mkdir -p "$other"
  (cd "$other" && git init -q && git remote add origin https://github.com/acme/cohabitat.git)
  run bash "$TOOLS" env-context "$other"
  [ "$output" = "installed" ]
}
