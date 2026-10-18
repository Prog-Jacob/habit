#!/usr/bin/env bats
# Distill runs over the inbox: claim, finish, snapshot, undo.

load test_helper

setup() {
  H=$(new_home inb)
  G="$H/.claude/habits"
  touch "$G/.v3"
  REPO="$(cd "$H" && pwd -P)/repo"
  mkdir -p "$REPO/.claude/habits" "$REPO/src" "$G/inbox"
  _write_habit "$G/keep.md" keep "[k]" "Kept habit." global false "Original body."
  _write_habit "$REPO/.claude/habits/proj.md" proj "[p]" "Project habit." project false "Project body."
}

# line <sid> <cwd> <prompt> [ctx]
line() {
  jq -nc --arg s "$1" --arg c "$2" --arg p "$3" --arg x "${4:-}" \
    '{ts: "2026-10-18T10:00:00Z", host: "claude", sid: $s, cwd: $c, prompt: $p} + (if $x != "" then {ctx: $x} else {} end)'
}

@test "claim prints EMPTY when the inbox is empty" {
  run hx "$H" "$H" claim
  [ "$output" = "EMPTY" ]
  [ ! -d "$G/inbox/.claimed" ]
}

@test "claim groups prompts by project, shows ctx, skips torn lines, and snapshots" {
  line abcdef123456 "$REPO/src" "fix the repo bug now" "Want me to also fix the docs?" > "$G/inbox/claude-abcdef123456.jsonl"
  echo '{"torn' >> "$G/inbox/claude-abcdef123456.jsonl"
  line zz9 "$H/elsewhere" "a global level prompt" > "$G/inbox/cursor-zz9.jsonl"
  run hx "$H" "$H" claim
  local run
  run=$(echo "$output" | sed -n 's/^RUN //p')
  [ -n "$run" ]
  [ "$(echo "$output" | sed -n 2p)" = "---PROJECT:global---" ]
  assert_contains "[2026-10-18T10:00:00Z claude zz9] a global level prompt" "$output"
  assert_contains "---PROJECT:$REPO---" "$output"
  assert_contains "$(printf '[2026-10-18T10:00:00Z claude abcdef12] fix the repo bug now\n  ctx: Want me to also fix the docs?')" "$output"
  refute_contains "torn" "$output"
  [ -z "$(ls "$G/inbox"/*.jsonl 2>/dev/null)" ]
  [ "$(ls "$G/inbox/.claimed/$run" | wc -l | tr -d ' ')" -eq 2 ]
  run tar -xzOf "$G/snapshots/$run.tar.gz" ./MANIFEST
  assert_contains "$G/keep.md" "$output"
  assert_contains "$REPO/.claude/habits/proj.md" "$output"
}

@test "claim snapshots the current project even when no prompt came from it" {
  line g1 "$H/elsewhere" "a prompt from somewhere else" > "$G/inbox/claude-g1.jsonl"
  local run
  run=$(hx "$H" "$REPO/src" claim | sed -n 's/^RUN //p')
  run tar -xzOf "$G/snapshots/$run.tar.gz" ./MANIFEST
  assert_contains "$REPO/.claude/habits/proj.md" "$output"
}

@test "an append in flight to a moved file lands in the claimed file" {
  local f="$G/inbox/claude-live.jsonl"
  line live "$H" "first prompt in session" > "$f"
  exec 7>>"$f"
  (cd "$H" && HOME="$H" bash "$TOOLS" claim > "$BATS_TEST_TMPDIR/claim.out") &
  local pid=$! i
  for i in $(seq 1 50); do [ -e "$f" ] || break; sleep 0.05; done
  [ ! -e "$f" ]
  line live "$H" "second prompt written late" >&7
  exec 7>&-
  wait "$pid"
  assert_contains "second prompt written late" "$(cat "$BATS_TEST_TMPDIR/claim.out")"
  local run
  run=$(sed -n 's/^RUN //p' "$BATS_TEST_TMPDIR/claim.out")
  [ "$(wc -l < "$G/inbox/.claimed/$run/claude-live.jsonl" | tr -d ' ')" -eq 2 ]
  [ ! -e "$f" ]
}

@test "an unfinished run is re-claimed by the next claim" {
  line s1 "$H" "prompt from the failed run" > "$G/inbox/claude-s1.jsonl"
  local first second
  first=$(hx "$H" "$H" claim | sed -n 's/^RUN //p')
  line s1 "$H" "prompt after the failure" > "$G/inbox/claude-s1.jsonl"
  run hx "$H" "$H" claim
  second=$(echo "$output" | sed -n 's/^RUN //p')
  [ "$first" != "$second" ]
  assert_contains "prompt from the failed run" "$output"
  assert_contains "prompt after the failure" "$output"
  [ ! -d "$G/inbox/.claimed/$first" ]
  [ "$(cat "$G/inbox/.claimed/$second"/*.jsonl | wc -l | tr -d ' ')" -eq 2 ]
}

@test "claim stops at 400 lines in whole files but always takes one file" {
  local i n m=0
  for n in a b c; do
    for i in $(seq 1 250); do line "$n" "$H" "prompt $i of file $n"; done > "$G/inbox/claude-$n.jsonl"
    m=$((m + 1))
    touch -t "20261001000$m" "$G/inbox/claude-$n.jsonl"
  done
  local run out
  out=$(hx "$H" "$H" claim)
  run=$(echo "$out" | sed -n 's/^RUN //p')
  [ "$(echo "$out" | sed -n 2p)" = "REMAINING 250" ]
  [ "$(ls "$G/inbox/.claimed/$run" | wc -l | tr -d ' ')" -eq 2 ]
  [ "$(ls "$G/inbox"/*.jsonl)" = "$G/inbox/claude-c.jsonl" ]
  rm -rf "$G/inbox"
  mkdir -p "$G/inbox"
  for i in $(seq 1 900); do line big "$H" "prompt $i of the big file"; done > "$G/inbox/claude-big.jsonl"
  run=$(hx "$H" "$H" claim | sed -n 's/^RUN //p')
  [ "$(wc -l < "$G/inbox/.claimed/$run/claude-big.jsonl" | tr -d ' ')" -eq 900 ]
}

@test "finish moves the run to done and prunes old runs, snapshots, and log months" {
  line s1 "$H" "a prompt to finish" > "$G/inbox/claude-s1.jsonl"
  local run i
  run=$(hx "$H" "$H" claim | sed -n 's/^RUN //p')
  mkdir -p "$G/inbox/.done/20200101T000000Z" "$G/log"
  touch -t 202001010000 "$G/inbox/.done/20200101T000000Z"
  for i in 01 02 03 04 05 06 07 08 09 10 11; do : > "$G/snapshots/202001${i}T000000Z.tar.gz"; done
  : > "$G/log/2020-01.jsonl"
  : > "$G/log/$(date -u +%Y-%m).jsonl"
  run hx "$H" "$H" finish "$run"
  assert_contains "OK finished $run" "$output"
  [ -d "$G/inbox/.done/$run" ]
  [ ! -d "$G/inbox/.claimed/$run" ]
  [ ! -d "$G/inbox/.done/20200101T000000Z" ]
  [ "$(ls "$G/snapshots"/*.tar.gz | wc -l | tr -d ' ')" -eq 10 ]
  [ -f "$G/snapshots/$run.tar.gz" ]
  [ ! -f "$G/snapshots/20200101T000000Z.tar.gz" ]
  [ ! -f "$G/log/2020-01.jsonl" ]
  [ -f "$G/log/$(date -u +%Y-%m).jsonl" ]
  run hx "$H" "$H" finish "$run"
  [ "$status" -ne 0 ]
}

new_md() { printf -- '---\nid: %s\ndescription: %s\n---\n\n%s\n' "$1" "$2" "$3"; }

@test "undo deletes created files, restores merged ones, re-queues prompts, and is undoable" {
  line s1 "$REPO/src" "a prompt that made habits" > "$G/inbox/claude-s1.jsonl"
  local run
  run=$(hx "$H" "$H" claim | sed -n 's/^RUN //p')
  hx "$H" "$H" write-habit global fresh "$(new_md fresh 'Created by distill.' 'New.')" >/dev/null
  hx "$H" "$H" write-habit global keep "$(new_md keep 'Kept habit.' 'Merged body.')" >/dev/null
  (cd "$REPO/src" && HOME="$H" HABIT_PROJECT_DIR="$REPO" bash "$TOOLS" write-habit project proj "$(new_md proj 'Project habit.' 'Merged project.')") >/dev/null
  hx "$H" "$H" write-learning distill "a learning from the run" >/dev/null
  hx "$H" "$H" finish "$run" >/dev/null

  run hx "$H" "$H" undo
  assert_contains "UNDO $run" "$output"
  assert_contains "$G/fresh.md" "$output"
  assert_contains "$G/keep.md" "$output"
  assert_contains "$REPO/.claude/habits/proj.md" "$output"
  assert_contains "$G/learnings.jsonl" "$output"
  [ ! -f "$G/fresh.md" ]
  assert_contains "Original body." "$(cat "$G/keep.md")"
  assert_contains "Project body." "$(cat "$REPO/.claude/habits/proj.md")"
  [ ! -f "$G/learnings.jsonl" ]
  [ -d "$G/inbox/.claimed/$run" ]
  [ ! -d "$G/inbox/.done/$run" ]

  local undo_run
  undo_run=$(ls "$G/snapshots" | sed -n 's/^\(undo-.*\)\.tar\.gz$/\1/p' | tail -n 1)
  [ -n "$undo_run" ]
  run hx "$H" "$H" undo "$undo_run"
  assert_contains "$G/fresh.md" "$output"
  [ -f "$G/fresh.md" ]
  assert_contains "Merged body." "$(cat "$G/keep.md")"
  assert_contains "Merged project." "$(cat "$REPO/.claude/habits/proj.md")"
  assert_contains "a learning from the run" "$(cat "$G/learnings.jsonl")"
  [ -d "$G/inbox/.done/$run" ]
  [ ! -d "$G/inbox/.claimed/$run" ]
}

@test "undo with no distill run says so and changes nothing" {
  run hx "$H" "$H" undo
  [ "$output" = "Nothing to undo" ]
  [ ! -d "$G/snapshots" ] || [ -z "$(ls "$G/snapshots")" ]
}

@test "snapshot on an empty inbox makes a distill run that undo restores" {
  run hx "$H" "$REPO/src" claim
  [ "$output" = "EMPTY" ]
  run hx "$H" "$REPO/src" snapshot maintain
  local run
  run=$(echo "$output" | sed -n 's/^RUN //p')
  [[ "$run" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
  [ "$(tar -xzOf "$G/snapshots/$run.tar.gz" ./LABEL)" = maintain ]
  assert_contains "$REPO/.claude/habits/proj.md" "$(tar -xzOf "$G/snapshots/$run.tar.gz" ./MANIFEST)"
  hx "$H" "$H" write-habit global keep "$(new_md keep 'Kept habit.' 'Rewritten as a rule.')" >/dev/null
  hx "$H" "$H" write-habit global added "$(new_md added 'Added by maintain.' 'New.')" >/dev/null
  (cd "$REPO/src" && HOME="$H" bash "$TOOLS" write-habit project proj "$(new_md proj 'Project habit.' 'Changed.')") >/dev/null
  run hx "$H" "$REPO/src" undo
  assert_contains "UNDO $run" "$output"
  refute_contains "requeued" "$output"
  assert_contains "Original body." "$(cat "$G/keep.md")"
  assert_contains "Project body." "$(cat "$REPO/.claude/habits/proj.md")"
  [ ! -f "$G/added.md" ]
  [ ! -d "$G/inbox/.claimed" ]
}
