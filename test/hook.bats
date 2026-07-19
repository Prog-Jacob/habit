#!/usr/bin/env bats
# Hook adapter tests: per-platform payloads, lazy init, breadcrumb concurrency,
# symlinked self-location.

load test_helper

@test "hook prompt-tick via a Claude Code payload counts the prompt and stores the transcript" {
  local home="$BATS_TEST_TMPDIR/cc1"
  mkdir -p "$home/.claude/habits"
  local tp="$home/transcript.jsonl"
  echo '{"type":"user","message":{"content":"seed"}}' > "$tp"
  echo '{"session_id":"cc-sid-1"}' | HOME="$home" bash "$HOOK" session-init >/dev/null 2>&1
  printf '{"session_id":"cc-sid-1","prompt":"this prompt has definitely more than five words","transcript_path":"%s"}' "$tp" \
    | HOME="$home" bash "$HOOK" prompt-tick >/dev/null 2>&1
  run bash -c "HOME='$home' bash '$TOOLS' read-prompt-count cc-sid-1"
  [ "$output" = "1" ]
  run jq -r '.sessions["cc-sid-1"].transcript_path' "$home/.claude/habits/settings.local.json"
  [ "$output" = "$tp" ]
}

@test "hook prompt-tick via a Cursor payload lazily creates the session and counts the prompt" {
  local home="$BATS_TEST_TMPDIR/cur1"
  mkdir -p "$home/.claude/habits"
  local ws="$home/work"
  mkdir -p "$ws"
  printf '{"conversation_id":"cur-sid-1","prompt":"this cursor prompt also has plenty of words","workspace_roots":["%s"]}' "$ws" \
    | HOME="$home" bash "$HOOK" prompt-tick >/dev/null 2>&1
  run bash -c "HOME='$home' bash '$TOOLS' read-prompt-count cur-sid-1"
  [ "$output" = "1" ]
  [ -f "$home/.claude/habits/sessions.d/cur-sid-1" ]
}

@test "hook session-init writes a per-session breadcrumb for a Claude Code payload" {
  local home="$BATS_TEST_TMPDIR/si1"
  echo '{"session_id":"cc-sid-2"}' | HOME="$home" bash "$HOOK" session-init >/dev/null 2>&1
  run cat "$home/.claude/habits/sessions.d/cc-sid-2"
  assert_contains "HABIT_SID=cc-sid-2" "$output"
}

@test "hook session-init writes a per-session breadcrumb for a Cursor payload with no id" {
  local home="$BATS_TEST_TMPDIR/si2"
  echo '{}' | HOME="$home" bash "$HOOK" session-init >/dev/null 2>&1
  local file
  file=$(ls "$home/.claude/habits/sessions.d/" 2>/dev/null | head -1)
  [ -n "$file" ]
  case "$file" in cursor-*) ;; *) false ;; esac
  run cat "$home/.claude/habits/sessions.d/$file"
  assert_contains "HABIT_SID=cursor-" "$output"
}

@test "hook prompt-tick with an empty prompt makes no state change" {
  local home="$BATS_TEST_TMPDIR/ep1"
  echo '{"session_id":"cc-sid-3","prompt":""}' | HOME="$home" bash "$HOOK" prompt-tick >/dev/null 2>&1
  [ ! -f "$home/.claude/habits/settings.local.json" ]
  [ ! -d "$home/.claude/habits/sessions.d" ]
}

@test "hook prompt-tick with a missing prompt field makes no state change" {
  local home="$BATS_TEST_TMPDIR/ep2"
  echo '{"session_id":"cc-sid-4"}' | HOME="$home" bash "$HOOK" prompt-tick >/dev/null 2>&1
  [ ! -f "$home/.claude/habits/settings.local.json" ]
}

@test "two session-inits keep independent breadcrumbs and session-end clears only its own" {
  local home="$BATS_TEST_TMPDIR/cz1"
  HOME="$home" bash "$TOOLS" session-init sess-A >/dev/null
  HOME="$home" bash "$TOOLS" session-init sess-B >/dev/null
  [ -f "$home/.claude/habits/sessions.d/sess-A" ]
  [ -f "$home/.claude/habits/sessions.d/sess-B" ]
  run cat "$home/.claude/habits/current"
  assert_contains "HABIT_SID=sess-B" "$output"

  HOME="$home" bash "$TOOLS" session-end sess-A >/dev/null
  [ ! -f "$home/.claude/habits/sessions.d/sess-A" ]
  [ -f "$home/.claude/habits/sessions.d/sess-B" ]
  run cat "$home/.claude/habits/current"
  assert_contains "HABIT_SID=sess-B" "$output"

  HOME="$home" bash "$TOOLS" session-end sess-B >/dev/null
  [ ! -f "$home/.claude/habits/sessions.d/sess-B" ]
  [ ! -f "$home/.claude/habits/current" ]
}

@test "a symlinked hook resolves the real plugin root and processes the event" {
  local home="$BATS_TEST_TMPDIR/sym1"
  local linkdir="$BATS_TEST_TMPDIR/symlink-home"
  mkdir -p "$linkdir"
  ln -s "$HOOK" "$linkdir/habit-hook.sh"
  echo '{"session_id":"sym-sid-1"}' \
    | env -u CLAUDE_PLUGIN_ROOT -u CURSOR_PLUGIN_ROOT HOME="$home" bash "$linkdir/habit-hook.sh" session-init >/dev/null 2>&1
  [ -f "$home/.claude/habits/sessions.d/sym-sid-1" ]
}
