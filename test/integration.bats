#!/usr/bin/env bats
# Integration tests: the CLI end to end for preload, watch, learnings, and
# env detection. status lives in status.bats; hook routing in hook.bats and
# static.bats.

load test_helper

# --- preload ---

# sections <output>: the ===NAME=== headers in order, space separated.
sections() { echo "$1" | sed -n 's/^===\([A-Z]*\)===$/\1/p' | tr '\n' ' '; }

@test "preload emits the sections each skill reads" {
  local h
  h=$(new_home pl)
  touch "$h/.claude/habits/.v3"
  _write_habit "$h/.claude/habits/alpha.md" alpha "[a]" "Alpha habit." global false "A."
  _write_habit "$h/.claude/habits/gone.md" gone "[g]" "Archived habit." global true "G."
  hx "$h" "$h" write-learning suggest "prefer narrow habits" >/dev/null
  hx "$h" "$h" log-exec '[{"scope":"global","id":"alpha"}]' sid-1 >/dev/null

  run hx "$h" "$h" preload suggest
  [ "$(sections "$output")" = "LEARNINGS INDEX " ]
  assert_contains "prefer narrow habits" "$output"
  assert_contains '"alpha"' "$output"
  refute_contains '"gone"' "$output"

  run hx "$h" "$h" preload habit
  [ "$(sections "$output")" = "LEARNINGS INDEX " ]
  refute_contains "prefer narrow habits" "$output"

  run hx "$h" "$h" preload edit
  [ "$(sections "$output")" = "LEARNINGS PROCESSING " ]
  assert_contains "Habit Processing Rules" "$output"

  run hx "$h" "$h" preload distill
  [ "$(sections "$output")" = "LEARNINGS INDEX LOG CONTEXT PROCESSING OPERATIONS " ]
  assert_contains '"gone"' "$output"
  assert_contains '"sid":"sid-1"' "$output"
  assert_contains "Habit Operations Reference" "$output"

  run hx "$h" "$h" preload watch
  assert_contains "Capture: ACTIVE" "$output"
  assert_contains "Distill: not due" "$output"
  refute_contains "===" "$output"

  run hx "$h" "$h" preload nope
  [ "$status" -ne 0 ]
}

@test "preload distill keeps the last 200 log lines" {
  local h i
  h=$(new_home pl2)
  touch "$h/.claude/habits/.v3"
  mkdir -p "$h/.claude/habits/log"
  for i in $(seq 1 250); do
    printf '{"ts":"2026-10-01T00:00:00Z","id":"h%s","project":"","sid":"","note":""}\n' "$i"
  done > "$h/.claude/habits/log/2026-10.jsonl"
  run hx "$h" "$h" preload distill
  local log
  log=$(echo "$output" | awk '/^===LOG===$/{f=1; next} /^===/{f=0} f && /^\{/')
  [ "$(echo "$log" | wc -l | tr -d ' ')" -eq 200 ]
  assert_contains '"id":"h250"' "$log"
  refute_contains '"id":"h50"' "$log"
}

@test "preload shows a failing section's error and still prints the rest" {
  local h
  h=$(new_home pl3)
  touch "$h/.claude/habits/.v3"
  [ "$(id -u)" -ne 0 ] || skip "root reads any file"
  _write_habit "$h/.claude/habits/locked.md" locked "[l]" "Unreadable." global false "L."
  chmod 000 "$h/.claude/habits/locked.md"
  run hx "$h" "$h" preload distill
  chmod 644 "$h/.claude/habits/locked.md"
  [ "$status" -eq 0 ]
  [ "$(sections "$output")" = "LEARNINGS INDEX LOG CONTEXT PROCESSING OPERATIONS " ]
  assert_contains "locked.md" "$(echo "$output" | awk '/^===INDEX===$/{f=1; next} /^===/{f=0} f')"
}

# --- watch ---

@test "watch off pauses capture until the expiry and watch on resumes it" {
  local h before
  h=$(new_home w1)
  touch "$h/.claude/habits/.v3"
  run hx "$h" "$h" watch
  assert_contains "Capture: ACTIVE" "$output"
  before=$(date +%s)
  run hx "$h" "$h" watch off 2
  assert_contains "PAUSED until " "$output"
  local until
  until=$(cat "$h/.claude/habits/paused")
  [ "$until" -ge $((before + 7200)) ]
  [ "$until" -le $(( $(date +%s) + 7200 )) ]
  [ -z "$(ls -A "$h/.claude/habits" | grep '^\.paused\.')" ]
  run hx "$h" "$h" watch status
  assert_contains "Capture: PAUSED until " "$output"
  printf '{"session_id":"w-1","cwd":"/w","prompt":"this prompt is not captured"}' | HOME="$h" bash "$TOOLS" capture
  [ ! -e "$h/.claude/habits/inbox/claude-w-1.jsonl" ]
  run hx "$h" "$h" watch on
  [ "$output" = "ACTIVE" ]
  [ ! -e "$h/.claude/habits/paused" ]
}

@test "watch off defaults to 8 hours and rejects a bad duration" {
  local h before
  h=$(new_home w2)
  touch "$h/.claude/habits/.v3"
  before=$(date +%s)
  hx "$h" "$h" watch off >/dev/null
  [ "$(cat "$h/.claude/habits/paused")" -ge $((before + 28800)) ]
  for bad in 0 -1 abc 1.5 8761; do
    run hx "$h" "$h" watch off "$bad"
    [ "$status" -ne 0 ]
  done
  run hx "$h" "$h" watch sideways
  [ "$status" -ne 0 ]
}

@test "watch snooze sets the reminder epoch, defaults to 7 days, and rejects bad days" {
  local h g before
  h=$(new_home sn); g="$h/.claude/habits"
  touch "$g/.v3"
  before=$(date +%s)
  run hx "$h" "$h" watch snooze 3
  assert_contains "Distill reminders snoozed until " "$output"
  [ "$(cat "$g/nudge.next")" -ge $((before + 259200)) ]
  [ "$(cat "$g/nudge.next")" -le $(( $(date +%s) + 259200 )) ]
  [ -z "$(ls -A "$g" | grep '^\.nudge\.next\.')" ]
  hx "$h" "$h" watch snooze >/dev/null
  [ "$(cat "$g/nudge.next")" -ge $((before + 604800)) ]
  run hx "$h" "$h" watch
  assert_contains "Distill: not due (reminders snoozed until " "$output"
  for bad in 0 abc 366 2.5; do
    run hx "$h" "$h" watch snooze "$bad"
    [ "$status" -ne 0 ]
  done
}

@test "status numbers the learnings and says how to forget one" {
  local h
  h=$(new_home wf)
  touch "$h/.claude/habits/.v3"
  hx "$h" "$h" write-learning suggest "first note" >/dev/null
  hx "$h" "$h" write-learning edit "second note" >/dev/null
  run hx "$h" "$h" status
  assert_contains "$(printf 'Learnings:\n  1. [suggest] first note\n  2. [edit] second note\n  Forget one with: watch forget <n>')" "$output"
}

# --- learnings and environment ---

@test "read-learnings tolerates a state file predating the learnings key" {
  local home="$BATS_TEST_TMPDIR/lrn-old"
  mkdir -p "$home/.claude/habits"
  printf '%s' '{"index":[],"meta":{},"log":[],"sessions":{},"observations":[]}' > "$home/.claude/habits/settings.local.json"
  run bash -c "HOME='$home' bash '$TOOLS' read-learnings run"
  [ -z "$output" ]
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

@test "an unknown or missing command prints the usage to stderr only and exits 1" {
  local h c
  h=$(new_home usage)
  for c in bogus ""; do
    run bash -c 'HOME="$1" bash "$2" $3 2>&1 >/dev/null' _ "$h" "$TOOLS" "$c"
    [ "$status" -eq 1 ]
    assert_contains "Usage: habit-tools.sh <command> [args]" "$output"
    [ -z "$(HOME="$h" bash "$TOOLS" $c 2>/dev/null)" ]
  done
  [ -z "$(ls -A "$h/.claude/habits")" ]
}
