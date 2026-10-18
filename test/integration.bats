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

@test "watch forget is forget-learning, and status numbers the learnings" {
  local h
  h=$(new_home wf)
  touch "$h/.claude/habits/.v3"
  hx "$h" "$h" write-learning suggest "first note" >/dev/null
  hx "$h" "$h" write-learning edit "second note" >/dev/null
  run hx "$h" "$h" status
  assert_contains "$(printf 'Learnings:\n  1. [suggest] first note\n  2. [edit] second note\n  Forget one with: watch forget <n>')" "$output"
  run hx "$h" "$h" watch forget 1
  [ "$output" = "OK forgot learning 1" ]
  [ "$(hx "$h" "$h" list-learnings)" = "1. [edit] second note" ]
  run hx "$h" "$h" watch forget 9
  [ "$status" -ne 0 ]
}

# A HOME with two Claude installs in the install record, a leftover cache dir,
# one Cursor copy, and an unrelated Cursor plugin.
seed_copies() {
  mkdir -p "$1/.claude/plugins/cache/mk/habit/2.0.0" "$1/.cursor/plugins/cache/cp/habit/abc/.cursor-plugin" \
    "$1/.cursor/plugins/cache/cp/figma/def/.cursor-plugin"
  jq -n '{plugins: {"habit@mk": [{version: "2.1.0"}], "habit@other": [{version: "2.2.0"}], "figma@mk": [{version: "1.0.0"}]}}' \
    > "$1/.claude/plugins/installed_plugins.json"
  echo '{"name":"habit","version":"2.2.0"}' > "$1/.cursor/plugins/cache/cp/habit/abc/.cursor-plugin/plugin.json"
  echo '{"name":"figma","version":"1.0.0"}' > "$1/.cursor/plugins/cache/cp/figma/def/.cursor-plugin/plugin.json"
}

@test "status flags extra copies and a v2 copy still writing, and shows each section" {
  local h g out
  h=$(new_home st); g="$h/.claude/habits"
  seed_copies "$h"
  seed_shim "$h"
  touch -t 202610010000 "$g/.v3"
  echo '{"log":[]}' > "$g/settings.local.json"
  seed_inbox "$g/inbox/claude-s1.jsonl" 10 8 2
  seed_inbox "$g/inbox/claude-backfill-00.jsonl" 5 20
  seed_inbox "$g/inbox/.done/r0/cursor-c1.jsonl" 3 9
  touch -t 202610050930 "$g/inbox/claude-s1.jsonl"
  touch -t 202610060930 "$g/inbox/.done/r0/cursor-c1.jsonl"
  _write_habit "$g/alpha.md" alpha "[a]" "Alpha habit." global false "Body text."
  printf -- '---\nid: rule-one\ndescription: A rule.\nkind: rule\narchived: false\n---\n0123456789\n' > "$g/rule-one.md"
  _write_habit "$g/gone.md" gone "[g]" "Archived." global true "G."
  mkdir -p "$g/snapshots"
  touch "$g/snapshots/migrate-20261002T000000Z.tar.gz" "$g/snapshots/20261003T101500Z.tar.gz" \
    "$g/snapshots/undo-20261004T000000Z.tar.gz"
  run hx "$h" "$h" status
  [ "$status" -eq 0 ]
  out="$output"
  assert_contains "Version: $(jq -r .version "$REPO_ROOT/.claude-plugin/plugin.json") running from $REPO_ROOT" "$out"
  assert_contains "Shim: $TOOLS" "$out"
  assert_contains "claude habit@mk 2.1.0" "$out"
  assert_contains "claude habit@other 2.2.0" "$out"
  assert_contains "/.cursor/plugins/cache/cp/habit/abc 2.2.0" "$out"
  assert_contains "  cursor /" "$out"
  refute_contains "figma" "$out"
  refute_contains "cache/mk/habit/2.0.0" "$out"
  assert_contains "WARN: 3 installed copies. One install per machine is enough" "$out"
  assert_contains "WARN: v2 code is still writing settings.local.json" "$out"
  refute_contains "v2 leftovers" "$out"
  assert_contains "Last capture: claude 2026-10-05 09:30, cursor 2026-10-06 09:30" "$out"
  assert_contains "Backlog: 15 prompts, oldest $(date -r $(( $(date +%s) - 20 * 86400 )) +%Y-%m-%d 2>/dev/null || date -d "-20 days" +%Y-%m-%d)" "$out"
  assert_contains "Distill: not due" "$out"
  assert_contains "(20261003T101500Z)" "$out"
  assert_contains "Habits: 2 active, 1 archived, 1 unclassified, 0 invalid" "$out"
  assert_contains "Rule budget: 11/8000 chars" "$out"
  assert_contains "Integrity: OK" "$out"
}

@test "status lists v2 leftovers once no v2 copy writes" {
  local h g
  h=$(new_home stl); g="$h/.claude/habits"
  seed_shim "$h"
  mkdir -p "$g/sessions.d"
  echo '{}' > "$g/settings.local.json"
  touch "$g/_meta.json"
  touch -t 202601010000 "$g/settings.local.json"
  touch "$g/.v3"
  run hx "$h" "$h" status
  [ "$status" -eq 0 ]
  assert_contains "v2 leftovers you can delete from $g: settings.local.json sessions.d _meta.json" "$output"
  refute_contains "WARN" "$output"
}

@test "status prints every section, then exits non-zero on an integrity failure" {
  local h g
  h=$(new_home sti); g="$h/.claude/habits"
  seed_shim "$h"
  touch "$g/.v3"
  seed_inbox "$g/inbox/claude-s1.jsonl" 2 0
  printf '{"ts":"2026-10-01T00:00:00Z","prom' >> "$g/inbox/claude-s1.jsonl"
  run hx "$h" "$h" status
  [ "$status" -ne 0 ]
  assert_contains "Learnings: none" "$output"
  assert_contains "$(printf 'FAIL: torn lines in inbox files:\n  %s' "$g/inbox/claude-s1.jsonl")" "$output"
  refute_contains "Integrity: OK" "$output"
  rm -rf "$g/inbox" "$g/.v3" "$g/bin"
  printf -- '---\nid: wrong\ndescription: Bad.\n---\n' > "$g/bad.md"
  run hx "$h" "$h" status
  [ "$status" -ne 0 ]
  assert_contains "FAIL: the shim target is missing" "$output"
  assert_contains "FAIL: .v3 is missing" "$output"
  assert_contains "bad.md: id wrong does not match the filename" "$output"
  [ ! -f "$g/.v3" ]
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
