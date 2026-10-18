#!/usr/bin/env bats
# Integration tests: the CLI end to end for preload, watch, learnings, and
# env detection. Hook routing lives in hook.bats and static.bats.

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
  [ "$(sections "$output")" = "LEARNINGS INDEX LOG PROCESSING OPERATIONS " ]
  assert_contains '"gone"' "$output"
  assert_contains '"sid":"sid-1"' "$output"
  assert_contains "Habit Operations Reference" "$output"

  run hx "$h" "$h" preload watch
  [ "$(echo "$output" | head -n 1)" = "ACTIVE" ]
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
  _write_habit "$h/.claude/habits/locked.md" locked "[l]" "Unreadable." global false "L."
  chmod 000 "$h/.claude/habits/locked.md"
  run hx "$h" "$h" preload distill
  chmod 644 "$h/.claude/habits/locked.md"
  [ "$status" -eq 0 ]
  [ "$(sections "$output")" = "LEARNINGS INDEX LOG PROCESSING OPERATIONS " ]
  assert_contains "locked.md" "$(echo "$output" | awk '/^===INDEX===$/{f=1; next} /^===/{f=0} f')"
}

# --- watch ---

@test "watch off pauses capture until the expiry and watch on resumes it" {
  local h before
  h=$(new_home w1)
  touch "$h/.claude/habits/.v3"
  run hx "$h" "$h" watch
  [ "$(echo "$output" | head -n 1)" = "ACTIVE" ]
  before=$(date +%s)
  run hx "$h" "$h" watch off 2
  assert_contains "PAUSED until " "$output"
  local until
  until=$(cat "$h/.claude/habits/paused")
  [ "$until" -ge $((before + 7200)) ]
  [ "$until" -le $(( $(date +%s) + 7200 )) ]
  [ -z "$(ls -A "$h/.claude/habits" | grep '^\.paused\.')" ]
  run hx "$h" "$h" watch status
  assert_contains "PAUSED until " "$(echo "$output" | head -n 1)"
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
  for bad in 0 -1 abc 1.5; do
    run hx "$h" "$h" watch off "$bad"
    [ "$status" -ne 0 ]
  done
  run hx "$h" "$h" watch sideways
  [ "$status" -ne 0 ]
}

@test "watch status counts waiting prompts and shows the newest capture" {
  local h g
  h=$(new_home w3)
  g="$h/.claude/habits"
  touch "$g/.v3"
  run hx "$h" "$h" watch
  [ "$output" = "$(printf 'ACTIVE\nInbox: 0 prompts waiting for distill\nLast capture: none')" ]
  mkdir -p "$g/inbox/.claimed/r1" "$g/inbox/.done/r0"
  printf '{"ts":"2026-10-01T10:00:00Z","prompt":"a"}\n{"ts":"2026-10-02T10:00:00Z","prompt":"b"}\n' > "$g/inbox/claude-a.jsonl"
  printf '{"ts":"2026-10-03T10:00:00Z","prompt":"c"}\n' > "$g/inbox/.claimed/r1/claude-b.jsonl"
  printf '{"ts":"2026-10-09T10:00:00Z","prompt":"d"}\n' > "$g/inbox/.done/r0/claude-c.jsonl"
  run hx "$h" "$h" watch
  assert_contains "Inbox: 3 prompts waiting for distill" "$output"
  local epoch
  epoch=$(jq -n '"2026-10-09T10:00:00Z" | fromdateiso8601')
  assert_contains "Last capture: $(date -r "$epoch" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$epoch" '+%Y-%m-%d %H:%M')" "$output"
}

# --- learnings and environment ---

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
