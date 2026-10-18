#!/usr/bin/env bats
# migrate (v2 state to v3 files), the history.jsonl backfill, and the
# session-start shim.

load test_helper

# A 2.0.0-shaped global and project state, with habits and a work dir.
seed_v2() {
  H=$(new_home mig)
  G="$H/.claude/habits"
  REPO="$(cd "$H" && pwd -P)/repo"
  mkdir -p "$REPO/.claude/habits" "$H/plain"
  _write_habit "$G/alpha.md" alpha "[a]" "Alpha habit." global false "A."
  awk '{ print } /^archived:/ { print "last_executed: 2026-09-15T10:00:00Z" }' "$G/alpha.md" > "$G/alpha.tmp" && mv "$G/alpha.tmp" "$G/alpha.md"
  _write_habit "$G/beta.md" beta "[b]" "Beta habit." global false "B."
  cat > "$G/settings.local.json" << 'JSON'
{"index":[{"id":"alpha","tags":["a"],"description":"Alpha habit.","scope":"global","archived":false,"last_executed":"2026-09-15T10:00:00Z"},{"id":""}],
 "meta":{"update_counter":3,"last_deep_timestamp":null,"version":"2.0.0",
   "distilled_project_sessions":{"/x/a.jsonl":"1700000000","../x/a.jsonl":"1700000000"},
   "pending_sessions":[{"session_id":"s1","transcript_path":"/t/s1.jsonl","prompt_count":4,"timestamp":"2026-10-01T00:00:00Z"}]},
 "log":[{"id":"alpha","override":"only auth","timestamp":"2026-09-15T10:00:00Z","scope":"global"},
        {"id":"beta","override":"","timestamp":"2026-10-02T08:00:00Z","scope":"global"},
        {"id":"","override":"junk","timestamp":"2026-10-02T08:00:00Z","scope":"global"}],
 "sessions":{"s2":{"prompt_count":2,"transcript_path":"","watch_paused":false,"init_time":"2026-10-17T00:00:00Z"}},
 "observations":[],
 "learnings":[{"target":"run","note":"scope overrides to the module","origin":"obs1","created":"2026-09-01T00:00:00Z"},
              {"target":"global","note":"summaries stay short","origin":"","created":"2026-09-02T00:00:00Z"}]}
JSON
  _write_habit "$REPO/.claude/habits/proj-h.md" proj-h "[p]" "Project habit." project false "P."
  awk '{ print } /^archived:/ { print "last_executed: 2026-08-20T09:00:00Z" }' "$REPO/.claude/habits/proj-h.md" > "$G/p.tmp" && mv "$G/p.tmp" "$REPO/.claude/habits/proj-h.md"
  cat > "$REPO/.claude/habits/settings.local.json" << 'JSON'
{"index":[{"id":"proj-h","scope":"project"}],"meta":{"update_counter":0},
 "log":[{"id":"proj-h","override":"p only","timestamp":"2026-08-20T09:00:00Z","scope":"project"}],"sessions":{},"observations":[]}
JSON
  cp "$G/settings.local.json" "$BATS_TEST_TMPDIR/g.before"
  cp "$REPO/.claude/habits/settings.local.json" "$BATS_TEST_TMPDIR/p.before"
}

@test "migrate converts learnings, logs, and seeds, and leaves v2 files byte-identical" {
  seed_v2
  run hx "$H" "$REPO" migrate
  [ "$output" = "OK v3" ]
  [ "$(cat "$G/.v3")" = "3" ]
  cmp "$G/settings.local.json" "$BATS_TEST_TMPDIR/g.before"
  cmp "$REPO/.claude/habits/settings.local.json" "$BATS_TEST_TMPDIR/p.before"

  run hx "$H" "$REPO" list-learnings
  [ "$output" = "$(printf '1. [run] scope overrides to the module\n2. [global] summaries stay short')" ]

  run hx "$H" "$REPO" read-log
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 5 ]
  [ "$(echo "$output" | jq -r 'select(.note=="only auth") | .project')" = "" ]
  [ "$(echo "$output" | jq -r 'select(.note=="p only") | .project')" = "$REPO" ]
  [ "$(echo "$output" | jq -r 'select(.note=="seed") | .id' | sort | tr '\n' ' ')" = "alpha proj-h " ]
  [ -z "$(echo "$output" | jq -r 'select(.id=="") | .id')" ]
  [ -f "$G/log/2026-08.jsonl" ] && [ -f "$G/log/2026-09.jsonl" ] && [ -f "$G/log/2026-10.jsonl" ]

  [ "$(grep -cxF "$REPO" "$G/migrated-projects")" -eq 1 ]
  ls "$G"/snapshots/migrate-*.tar.gz
  [ ! -d "$G/migrate.lock" ]
  run hx "$H" "$REPO" read-index merged
  [ "$(echo "$output" | jq -r '.entries[] | select(.id=="beta") | .last_executed')" = "2026-10-02T08:00:00Z" ]
}

@test "a failed step leaves no .v3 and no lock, and the next call completes it" {
  seed_v2
  touch "$G/log"
  run hx "$H" "$H/plain" migrate
  [ ! -f "$G/.v3" ]
  [ ! -d "$G/migrate.lock" ]
  rm "$G/log"
  run hx "$H" "$H/plain" migrate
  [ "$output" = "OK v3" ]
  [ "$(wc -l < "$G/learnings.jsonl" | tr -d ' ')" -eq 2 ]
}

@test "concurrent migrations produce one result with no duplicate lines" {
  seed_v2
  local i
  for i in 1 2 3 4 5; do
    (cd "$REPO" && HOME="$H" bash "$TOOLS" migrate >/dev/null 2>&1) &
  done
  wait
  run hx "$H" "$REPO" read-log
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 5 ]
  [ "$(wc -l < "$G/learnings.jsonl" | tr -d ' ')" -eq 2 ]
  [ "$(ls "$G"/snapshots/migrate-*.tar.gz | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(wc -l < "$G/migrated-projects" | tr -d ' ')" -eq 1 ]
}

@test "a fresh lock makes migrate return quietly and a stale lock is taken over" {
  seed_v2
  mkdir "$G/migrate.lock"
  run hx "$H" "$H/plain" read-index global
  [ ! -f "$G/.v3" ]
  assert_contains '"alpha"' "$output"
  touch -t 202601010000 "$G/migrate.lock"
  run hx "$H" "$H/plain" migrate
  [ "$output" = "OK v3" ]
  [ ! -d "$G/migrate.lock" ]
}

@test "any CLI call migrates lazily, and another project migrates on first touch" {
  seed_v2
  run hx "$H" "$H/plain" read-index global
  [ -f "$G/.v3" ]
  [ ! -f "$G/migrated-projects" ]
  [ "$(hx "$H" "$H/plain" read-log | jq -r 'select(.project != "") | .id')" = "" ]
  hx "$H" "$REPO" read-index merged >/dev/null
  hx "$H" "$REPO" read-index merged >/dev/null
  [ "$(hx "$H" "$H/plain" read-log | jq -r 'select(.project != "") | .id' | sort | tr '\n' ' ')" = "proj-h proj-h " ]
  [ "$(grep -cxF "$REPO" "$G/migrated-projects")" -eq 1 ]
}

# history <days ago> <sessionId> <display>: one history.jsonl line.
history_line() {
  jq -nc --argjson d "$1" --arg s "$2" --arg t "$3" \
    '{display: $t, pastedContents: {}, timestamp: (((now - $d * 86400) * 1000) | floor), project: "/w/repo", sessionId: $s}'
}

@test "backfill keeps the last 30 days, drops duplicates, filters, and redacts" {
  local h
  h=$(new_home bf)
  {
    history_line 40 s-old "a prompt from long ago here"
    history_line 5 s-a "/habit:suggest fix the flaky test please"
    history_line 5 s-a "/habit:suggest fix the flaky test please"
    history_line 4 s-b "/habit:suggest fix the flaky test please"
    history_line 3 s-a "/cost"
    history_line 3 s-a "/grice ok"
    history_line 2 s-a "deploy with token=abc123 to staging now"
    echo '{"torn'
    history_line 1 s-c "/tmp/out.log is empty again"
  } > "$h/.claude/history.jsonl"
  run hx "$h" "$h" migrate
  local bf="$h/.claude/habits/inbox/claude-backfill-00.jsonl"
  [ "$(wc -l < "$bf" | tr -d ' ')" -eq 4 ]
  [ "$(jq -r .prompt "$bf" | head -n 1)" = "fix the flaky test please" ]
  [ "$(jq -r 'select(.sid=="s-b") | .prompt' "$bf")" = "fix the flaky test please" ]
  [ "$(jq -r 'select(.sid=="s-a") | .prompt' "$bf" | tail -n 1)" = "deploy with token=[redacted] to staging now" ]
  [ "$(jq -r 'select(.sid=="s-c") | [.host, .cwd, .prompt] | join("|")' "$bf")" = "claude|/w/repo|/tmp/out.log is empty again" ]
  refute_contains "long ago" "$(cat "$bf")"
  [ ! -f "$h/.claude/habits/backfill-skipped" ]
  run ls -l "$bf"
  [ "${output:0:10}" = "-rw-------" ]
}

@test "backfill splits into files of at most the inbox cap" {
  local h i
  h=$(new_home bfcap)
  for i in $(seq 1 401); do history_line 1 s-cap "prompt number $i goes here"; done > "$h/.claude/history.jsonl"
  run hx "$h" "$h" migrate
  [ "$(wc -l < "$h/.claude/habits/inbox/claude-backfill-00.jsonl" | tr -d ' ')" -eq 400 ]
  [ "$(wc -l < "$h/.claude/habits/inbox/claude-backfill-01.jsonl" | tr -d ' ')" -eq 1 ]
}

@test "backfill skips an unexpected format or a missing file and leaves a marker" {
  local h
  h=$(new_home bf2)
  echo '{"text":"no display here","when":1}' > "$h/.claude/history.jsonl"
  run hx "$h" "$h" migrate
  [ -f "$h/.claude/habits/backfill-skipped" ]
  [ ! -e "$h/.claude/habits/inbox/claude-backfill-00.jsonl" ]
  [ "$output" = "OK v3" ]
  local h2
  h2=$(new_home bf3)
  run hx "$h2" "$h2" migrate
  [ -f "$h2/.claude/habits/backfill-skipped" ]
}

# --- Shim ---

shim_target() { sed -n 's/^exec bash "\(.*\)" "\$@"$/\1/p' "$1"; }

@test "session-start writes an executable shim to this copy, migrates, and prints nothing" {
  local h
  h=$(new_home ss)
  run bash -c "echo '{\"session_id\":\"x\"}' | HOME='$h' bash '$TOOLS' session-start"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  local shim="$h/.claude/habits/bin/habit-tools.sh"
  [ "$(shim_target "$shim")" = "$(cd "$REPO_ROOT" && pwd -P)/bin/habit-tools.sh" ]
  assert_contains "# habit-shim $(jq -r .version "$REPO_ROOT/.claude-plugin/plugin.json")" "$(cat "$shim")"
  run ls -l "$shim"
  [ "${output:0:10}" = "-rwxr-xr-x" ]
  [ -f "$h/.claude/habits/.v3" ]
  run bash "$shim" env-context /nonexistent
  [ "$output" = "installed" ]
  local i
  for i in $(seq 1 50); do [ -f "$h/.claude/habits/backfill-skipped" ] && break; sleep 0.1; done
  [ -f "$h/.claude/habits/backfill-skipped" ]
}

@test "shim: a newer recorded version wins, older or equal is replaced, a missing target is rewritten" {
  local h fake shim ours
  h=$(new_home ss2)
  shim="$h/.claude/habits/bin/habit-tools.sh"
  ours="$(cd "$REPO_ROOT" && pwd -P)/bin/habit-tools.sh"
  fake="$BATS_TEST_TMPDIR/fake/bin/habit-tools.sh"
  mkdir -p "$(dirname "$fake")" "$(dirname "$shim")"
  touch "$fake"
  for v in 99.0.0 2.10.0; do
    printf '#!/bin/bash\n# habit-shim %s\nexec bash "%s" "$@"\n' "$v" "$fake" > "$shim"
    echo '{}' | HOME="$h" bash "$TOOLS" session-start
    [ "$(shim_target "$shim")" = "$fake" ]
  done
  for v in 0.9.9 "$(jq -r .version "$REPO_ROOT/.claude-plugin/plugin.json")" banana 2.1; do
    printf '#!/bin/bash\n# habit-shim %s\nexec bash "%s" "$@"\n' "$v" "$fake" > "$shim"
    echo '{}' | HOME="$h" bash "$TOOLS" session-start
    [ "$(shim_target "$shim")" = "$ours" ]
  done
  printf '#!/bin/bash\n# habit-shim 99.0.0\nexec bash "%s" "$@"\n' "$BATS_TEST_TMPDIR/gone/bin/habit-tools.sh" > "$shim"
  echo '{}' | HOME="$h" bash "$TOOLS" session-start
  [ "$(shim_target "$shim")" = "$ours" ]
}

@test "hook session-start routes to the CLI and prints nothing" {
  local h
  h=$(new_home ss3)
  run bash -c "echo '{\"session_id\":\"x\"}' | HOME='$h' bash '$HOOK' session-start"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$h/.claude/habits/bin/habit-tools.sh" ]
}
