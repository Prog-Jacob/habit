#!/usr/bin/env bats
# Integration tests: CLI end to end, breadcrumbs, session discovery, install
# linking, learnings store, env detection, and robustness against corrupt
# inputs. Hook-adapter tests live in hook.bats.

load test_helper

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

@test "write_breadcrumb records HABIT_BIN and HABIT_SID per session and in current" {
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
  run cat "$bc/sessions.d/sess-123"
  assert_contains "HABIT_SID=sess-123" "$output"
}

@test "clear_breadcrumb removes only its own session file and a matching current" {
  local bc="$BATS_TEST_TMPDIR/bc2"
  mkdir -p "$bc/sessions.d"
  printf 'HABIT_SID=x\n' > "$bc/sessions.d/x"
  printf 'HABIT_SID=y\n' > "$bc/sessions.d/y"
  printf 'HABIT_SID=y\n' > "$bc/current"
  bash -c "source '$REPO_ROOT/bin/lib/common.sh'; GLOBAL_DIR='$bc'; clear_breadcrumb x"
  [ ! -f "$bc/sessions.d/x" ]
  [ -f "$bc/sessions.d/y" ]
  [ -f "$bc/current" ]
  bash -c "source '$REPO_ROOT/bin/lib/common.sh'; GLOBAL_DIR='$bc'; clear_breadcrumb y"
  [ ! -f "$bc/sessions.d/y" ]
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

@test "skill-preload emits LEARNINGS, TRIGGERS, INDEX in order for an index-carrying skill" {
  local home="$BATS_TEST_TMPDIR/sp1"
  mkdir -p "$home/.claude/habits"
  run bash -c "HOME='$home' bash '$TOOLS' skill-preload habit sid1"
  assert_contains "===LEARNINGS===" "$output"
  assert_contains "===TRIGGERS===" "$output"
  assert_contains "===INDEX===" "$output"
  local l t i
  l=$(echo "$output" | grep -n '^===LEARNINGS===$' | head -1 | cut -d: -f1)
  t=$(echo "$output" | grep -n '^===TRIGGERS===$' | head -1 | cut -d: -f1)
  i=$(echo "$output" | grep -n '^===INDEX===$' | head -1 | cut -d: -f1)
  [ "$l" -lt "$t" ]
  [ "$t" -lt "$i" ]
}

@test "skill-preload run emits no INDEX section" {
  local home="$BATS_TEST_TMPDIR/sp2"
  mkdir -p "$home/.claude/habits"
  run bash -c "HOME='$home' bash '$TOOLS' skill-preload run sid1"
  assert_contains "===LEARNINGS===" "$output"
  assert_contains "===TRIGGERS===" "$output"
  refute_contains "===INDEX===" "$output"
}

@test "skill-preload watch emits TRIGGERS only: watch is learning-free" {
  local home="$BATS_TEST_TMPDIR/sp3"
  mkdir -p "$home/.claude/habits"
  run bash -c "HOME='$home' bash '$TOOLS' skill-preload watch sid1"
  assert_contains "===TRIGGERS===" "$output"
  refute_contains "===LEARNINGS===" "$output"
  refute_contains "===INDEX===" "$output"
}


@test "install links the repo under a present tool's skills dir" {
  local in="$BATS_TEST_TMPDIR/install"
  mkdir -p "$in/.cursor"
  HOME="$in" bash "$REPO_ROOT/install.sh" >/dev/null 2>&1 || true
  [ -L "$in/.cursor/skills/habit-plugin" ]
  [ -L "$in/.cursor/hooks/habit-hook.sh" ]
  [ -f "$in/.cursor/skills/habit-plugin/skills/habit-shared/PROCESSING.md" ]
}

@test "read-transcript survives a malformed jsonl and still reads good files" {
  local home="$BATS_TEST_TMPDIR/rs"
  mkdir -p "$home/.claude/habits"
  printf 'this is not json\n' > "$home/bad.jsonl"
  echo '{"type":"user","message":{"content":"a valid user prompt with several words here"}}' > "$home/good.jsonl"
  run bash -c "HOME='$home' bash '$TOOLS' read-transcript '$home/bad.jsonl'"
  [ "$status" -eq 0 ]
  assert_contains "No session data yet." "$output"
  run bash -c "HOME='$home' bash '$TOOLS' read-transcript '$home/good.jsonl'"
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

@test "session-end promotes a counted session to pending and drops the live session" {
  local home="$BATS_TEST_TMPDIR/se"
  mkdir -p "$home/.claude/habits"
  local tp="$home/t.jsonl"
  echo '{"type":"user","message":{"content":"a real prompt with several words"}}' > "$tp"
  HOME="$home" bash "$TOOLS" session-init sess-A >/dev/null
  HOME="$home" bash "$TOOLS" prompt-tick sess-A "$tp" "a real prompt with several words" >/dev/null
  HOME="$home" bash "$TOOLS" session-end sess-A >/dev/null

  local state="$home/.claude/habits/settings.local.json"
  [ "$(jq '[.meta.pending_sessions[] | select(.session_id=="sess-A")] | length' "$state")" -eq 1 ]
  [ "$(jq '.sessions["sess-A"] // "gone"' "$state")" = '"gone"' ]
}

@test "watch stop pauses prompt counting until watch start resumes it" {
  local home="$BATS_TEST_TMPDIR/wp"
  mkdir -p "$home/.claude/habits"
  HOME="$home" bash "$TOOLS" session-init sess-B >/dev/null

  HOME="$home" bash "$TOOLS" watch stop sess-B >/dev/null
  HOME="$home" bash "$TOOLS" prompt-tick sess-B "" "a prompt with plenty of words here" >/dev/null
  run bash -c "HOME='$home' bash '$TOOLS' read-prompt-count sess-B"
  [ "$output" = "0" ]

  HOME="$home" bash "$TOOLS" watch start sess-B >/dev/null
  HOME="$home" bash "$TOOLS" prompt-tick sess-B "" "another prompt with plenty of words" >/dev/null
  run bash -c "HOME='$home' bash '$TOOLS' read-prompt-count sess-B"
  [ "$output" = "1" ]
}

@test "prune-learnings keeps at most LEARN_RETAIN entries" {
  local home="$BATS_TEST_TMPDIR/lrn-bound"
  mkdir -p "$home/.claude/habits"
  for i in $(seq 1 45); do
    HOME="$home" bash "$TOOLS" write-learning run "distinct note number $i" "obs$i" >/dev/null
  done
  HOME="$home" bash "$TOOLS" prune-learnings >/dev/null
  [ "$(jq '.learnings | length' "$home/.claude/habits/settings.local.json")" -eq 40 ]
}

@test "self-heal rebuilds the index from the habit .md files on disk" {
  local home="$BATS_TEST_TMPDIR/sh"
  local dir="$home/.claude/habits"
  mkdir -p "$dir"
  cat > "$dir/one.md" << 'MD'
---
id: one
tags: [x]
description: First habit.
scope: global
archived: false
---

## Instruction
A.
MD
  cat > "$dir/two.md" << 'MD'
---
id: two
tags: [y]
description: Second habit.
scope: global
archived: true
---

## Instruction
B.
MD
  printf '%s' '{"index":[],"meta":{},"log":[],"sessions":{},"observations":[]}' > "$dir/settings.local.json"

  run bash -c "HOME='$home' bash '$TOOLS' self-heal global"
  assert_contains "rebuilt index with 2 entries" "$output"
  [ "$(jq '.index | length' "$dir/settings.local.json")" -eq 2 ]
  [ "$(jq -r '.index[] | select(.id=="two") | .archived' "$dir/settings.local.json")" = "true" ]
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
