#!/usr/bin/env bats
# v3 data layer: learnings.jsonl, project resolution, the derived index, and
# the usage log months.

load test_helper

# --- Learnings ---

@test "learnings append, list with numbers, and fold forget tombstones on read" {
  local h
  h=$(new_home lrn)
  hx "$h" "$h" write-learning run "scope overrides to the module" o1 >/dev/null
  hx "$h" "$h" write-learning global "summaries stay short" o2 >/dev/null
  hx "$h" "$h" write-learning edit "keep the id stable" o3 >/dev/null
  [ "$(wc -l < "$h/.claude/habits/learnings.jsonl" | tr -d ' ')" -eq 3 ]

  run hx "$h" "$h" list-learnings
  [ "$output" = "$(printf '1. [run] scope overrides to the module\n2. [global] summaries stay short\n3. [edit] keep the id stable')" ]

  run hx "$h" "$h" read-learnings run
  [ "$output" = "$(printf 'scope overrides to the module\nsummaries stay short')" ]

  cp "$h/.claude/habits/learnings.jsonl" "$BATS_TEST_TMPDIR/before"
  run hx "$h" "$h" forget-learning 2
  assert_contains "OK" "$output"
  # Append only: the old bytes are a prefix of the new file.
  [ "$(head -c "$(wc -c < "$BATS_TEST_TMPDIR/before")" "$h/.claude/habits/learnings.jsonl")" = "$(cat "$BATS_TEST_TMPDIR/before")" ]
  [ "$(tail -n 1 "$h/.claude/habits/learnings.jsonl" | jq -r 'has("forget")')" = "true" ]

  run hx "$h" "$h" list-learnings
  [ "$output" = "$(printf '1. [run] scope overrides to the module\n2. [edit] keep the id stable')" ]
  run hx "$h" "$h" read-learnings run
  [ "$output" = "scope overrides to the module" ]
}

@test "forget-learning rejects an out of range number and writes nothing" {
  local h
  h=$(new_home lrn2)
  hx "$h" "$h" write-learning run "only one" >/dev/null
  run hx "$h" "$h" forget-learning 5
  [ "$status" -ne 0 ]
  run hx "$h" "$h" forget-learning x
  [ "$status" -ne 0 ]
  [ "$(wc -l < "$h/.claude/habits/learnings.jsonl" | tr -d ' ')" -eq 1 ]
}

@test "learning ids are unique and carry the line shape" {
  local h
  h=$(new_home lrn3)
  hx "$h" "$h" write-learning run "first" origin-a >/dev/null
  hx "$h" "$h" write-learning run "second" >/dev/null
  [ "$(jq -r .id "$h/.claude/habits/learnings.jsonl" | sort -u | wc -l | tr -d ' ')" -eq 2 ]
  [ "$(head -n 1 "$h/.claude/habits/learnings.jsonl" | jq -c 'keys')" = '["id","note","origin","target","ts"]' ]
}

# --- Project resolution ---

resolve() { # resolve <home> <start>
  bash -c "source '$REPO_ROOT/bin/lib/common.sh'; source '$REPO_ROOT/bin/lib/project.sh'; HOME='$1'; GLOBAL_DIR='$1/.claude/habits'; cd '$2' && project_root"
}

@test "project_root finds the nearest ancestor with .claude/habits" {
  local h
  h=$(new_home pr1)
  mkdir -p "$h/outer/.claude/habits" "$h/outer/inner/.claude/habits" "$h/outer/inner/a/b"
  run resolve "$h" "$h/outer/inner/a/b"
  [ "$output" = "$(cd "$h/outer/inner" && pwd -P)" ]
  mkdir -p "$h/outer/c"
  run resolve "$h" "$h/outer/c"
  [ "$output" = "$(cd "$h/outer" && pwd -P)" ]
}

@test "project_root stops before HOME and never returns the global dir" {
  local h
  h=$(new_home pr2)
  mkdir -p "$h/work/sub"
  run resolve "$h" "$h/work/sub"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  run resolve "$h" "$h"
  [ "$status" -eq 1 ]
}

@test "project_root resolves a symlinked dir and compares physical paths" {
  local h real link
  h=$(new_home pr3)
  real="$BATS_TEST_TMPDIR/real"
  mkdir -p "$real/.claude/habits" "$real/x"
  link="$BATS_TEST_TMPDIR/link"
  ln -s "$real" "$link"
  run resolve "$h" "$link/x"
  [ "$output" = "$(cd "$real" && pwd -P)" ]
  # A HOME given through a symlink still stops the walk.
  ln -s "$h" "$BATS_TEST_TMPDIR/homelink"
  mkdir -p "$h/w"
  run bash -c "source '$REPO_ROOT/bin/lib/common.sh'; source '$REPO_ROOT/bin/lib/project.sh'; HOME='$BATS_TEST_TMPDIR/homelink'; GLOBAL_DIR=\"\$HOME/.claude/habits\"; cd '$h/w' && project_root"
  [ "$status" -eq 1 ]
}

@test "project resolution creates nothing, and HABIT_PROJECT_DIR overrides pwd" {
  local h
  h=$(new_home pr4)
  mkdir -p "$h/repo/.claude/habits" "$h/elsewhere"
  local before
  before=$(find "$h" | sort)
  run hx "$h" "$h/elsewhere" read-index project
  [ "$(find "$h" -path "$h/.claude" -prune -o -print | sort)" = "$(echo "$before" | grep -v "^$h/.claude")" ]
  _write_habit "$h/repo/.claude/habits/p.md" p "[x]" "Project p." project false "Body."
  run bash -c "cd '$h/elsewhere' && HOME='$h' HABIT_PROJECT_DIR='$h/repo' bash '$TOOLS' read-habit p"
  assert_contains "SCOPE:project" "$output"
}

@test "write-habit project creates the scope dir at HABIT_PROJECT_DIR only when none resolves" {
  local h
  h=$(new_home pr5)
  mkdir -p "$h/repo/sub"
  local md
  md=$(printf -- '---\nid: np\ndescription: New project habit.\n---\n\nBody.')
  run bash -c "cd '$h/repo/sub' && HOME='$h' HABIT_PROJECT_DIR='$h/repo' bash '$TOOLS' write-habit project np \"\$1\"" _ "$md"
  assert_contains "OK wrote" "$output"
  [ -f "$h/repo/.claude/habits/np.md" ]
  [ ! -e "$h/repo/sub/.claude" ]
  run bash -c "cd '$h/repo/sub' && HOME='$h' bash '$TOOLS' write-habit project np \"\$1\"" _ "$md"
  [ ! -e "$h/repo/sub/.claude" ]
}

# --- Derived index ---

@test "derived index entries carry the frontmatter fields in the v2 index shape" {
  seed_fixtures
  source_libs
  run cmd_read_index global
  [ "$(echo "$output" | jq -c '[.entries[].id]')" = '["cleanup-writing","old-habit","smart-tests"]' ]
  [ "$(echo "$output" | jq -c '.entries[0]')" = '{"id":"cleanup-writing","tags":["writing","quality"],"description":"Replace em dashes with natural punctuation.","scope":"global","created":"2026-05-04T00:00:00Z","updated":"2026-05-07T00:00:00Z","archived":false}' ]
  [ "$(echo "$output" | jq -r '.entries[] | select(.id=="old-habit") | .archived')" = "true" ]
  run cmd_read_index project
  [ "$(echo "$output" | jq -c '[.entries[] | [.id, .scope]]')" = '[["project-habit","project"]]' ]
  teardown_fixtures
}

@test "project entries shadow global ones with the same id" {
  seed_fixtures
  source_libs
  _write_habit "$TEST_PROJECT/smart-tests.md" smart-tests "[local]" "Project override." project false "Local."
  run cmd_read_index merged
  [ "$(echo "$output" | jq '[.entries[] | select(.id=="smart-tests")] | length')" -eq 1 ]
  [ "$(echo "$output" | jq -r '.entries[] | select(.id=="smart-tests") | .scope')" = "project" ]
  run cmd_read_index global
  [ "$(echo "$output" | jq -r '.entries[] | select(.id=="smart-tests") | .description')" = "Write focused tests." ]
  teardown_fixtures
}

@test "invalid habit files are skipped by the index and listed by invalid-habits" {
  seed_fixtures
  source_libs
  printf -- '---\nid: \ndescription: No id.\n---\n' > "$TEST_GLOBAL/-.md"
  printf -- '---\nid: other\ndescription: Wrong id.\n---\n' > "$TEST_GLOBAL/renamed.md"
  printf -- '---\nid: nodesc\n---\n' > "$TEST_PROJECT/nodesc.md"
  run cmd_read_index merged
  [ "$(echo "$output" | jq -c '[.entries[].id]')" = '["cleanup-writing","old-habit","project-habit","smart-tests"]' ]
  run cmd_invalid_habits
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 3 ]
  assert_contains "$TEST_GLOBAL/-.md: missing id" "$output"
  assert_contains "$TEST_GLOBAL/renamed.md: id other does not match the filename" "$output"
  assert_contains "$TEST_PROJECT/nodesc.md: missing description" "$output"
  teardown_fixtures
}

@test "last_executed comes from the newest log line per id and scope, else frontmatter" {
  seed_fixtures
  source_libs
  awk '{ print } /^archived: false$/ { print "last_executed: 2026-01-01T00:00:00Z" }' "$TEST_GLOBAL/smart-tests.md" > "$BATS_TEST_TMPDIR/st"
  mv "$BATS_TEST_TMPDIR/st" "$TEST_GLOBAL/smart-tests.md"
  mkdir -p "$TEST_GLOBAL/log"
  cat > "$TEST_GLOBAL/log/2026-09.jsonl" << JSONL
{"ts":"2026-09-01T00:00:00Z","id":"cleanup-writing","project":"","sid":"","note":""}
{"ts":"2026-09-03T00:00:00Z","id":"cleanup-writing","project":"","sid":"","note":""}
{"ts":"2026-09-09T00:00:00Z","id":"cleanup-writing","project":"/some/other/repo","sid":"","note":""}
{"ts":"2026-09-05T00:00:00Z","id":"project-habit","project":"$TEST_PROJECT_ROOT","sid":"","note":""}
{"torn
JSONL
  run cmd_read_index merged
  [ "$(echo "$output" | jq -r '.entries[] | select(.id=="cleanup-writing") | .last_executed')" = "2026-09-03T00:00:00Z" ]
  [ "$(echo "$output" | jq -r '.entries[] | select(.id=="project-habit") | .last_executed')" = "2026-09-05T00:00:00Z" ]
  [ "$(echo "$output" | jq -r '.entries[] | select(.id=="smart-tests") | .last_executed')" = "2026-01-01T00:00:00Z" ]
  [ "$(echo "$output" | jq -r '.entries[] | select(.id=="old-habit") | has("last_executed")')" = "false" ]
  teardown_fixtures
}

@test "the index carries kind when the frontmatter has it" {
  seed_fixtures
  source_libs
  printf -- '---\nid: ruled\ndescription: A rule.\nkind: rule\n---\nBody.\n' > "$TEST_GLOBAL/ruled.md"
  run cmd_read_index global
  [ "$(echo "$output" | jq -r '.entries[] | select(.id=="ruled") | .kind')" = "rule" ]
  [ "$(echo "$output" | jq -r '.entries[] | select(.id=="smart-tests") | has("kind")')" = "false" ]
  teardown_fixtures
}

# --- Usage log ---

@test "40 parallel log-exec calls lose no line" {
  local h i
  h=$(new_home lg)
  touch "$h/.claude/habits/.v3"
  for i in $(seq 1 40); do
    (cd "$h" && HOME="$h" bash "$TOOLS" log-exec "[{\"scope\":\"global\",\"id\":\"h$i\"}]" "sid-$i" >/dev/null) &
  done
  wait
  run hx "$h" "$h" read-log
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 40 ]
  [ "$(echo "$output" | jq -r .id | sort -u | wc -l | tr -d ' ')" -eq 40 ]
  ls "$h/.claude/habits/log/$(date -u +%Y-%m).jsonl"
}
