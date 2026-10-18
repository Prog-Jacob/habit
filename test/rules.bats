#!/usr/bin/env bats
# Standing rules: kind validation, preload rules (order, shadowing, budget,
# due and unclassified lines), the merged Claude SessionStart object, and the
# context files distill dedups against.

load test_helper

setup() {
  H=$(new_home rules)
  G="$H/.claude/habits"
  touch "$G/.v3"
  REPO="$(cd "$H" && pwd -P)/repo"
  P="$REPO/.claude/habits"
  mkdir -p "$P"
}

# hab <path> <id> <kind or ""> <body> [archived]
hab() {
  { printf -- '---\nid: %s\ndescription: Habit %s.\n' "$2" "$2"
    if [ -n "$3" ]; then printf 'kind: %s\n' "$3"; fi
    printf 'archived: %s\n---\n\n%s\n' "${5:-false}" "$4"; } > "$1"
}

rules() { hx "$H" "$REPO" preload rules; }

# chars <text>: its length in characters plus the trailing newline jq -r prints.
chars() { printf '%s\n' "$1" | jq -Rs length; }

@test "preload rules: global rules, then project rules that shadow by id, then procedures and INJECTED" {
  hab "$G/g-a.md" g-a rule "$(printf '## Instruction\n\nGlobal rule A.')"
  hab "$G/shared.md" shared rule "Global shared text."
  hab "$G/proc-x.md" proc-x "" "Steps for x."
  hab "$G/proc-y.md" proc-y procedure "Steps for y."
  hab "$G/arch.md" arch rule "Archived rule." true
  hab "$P/shared.md" shared rule "Project shared text."
  hab "$P/p-b.md" p-b rule "Project rule B."
  run rules
  [ "$status" -eq 0 ]
  local expect=(
    "These are the user's standing rules from habit. Follow them in this session."
    "### g-a" "Global rule A." "### p-b" "Project rule B." "### shared" "Project shared text."
    "Procedures (load with read-habit <id> when relevant): proc-x, proc-y"
    "1 unclassified habit: run /habit:distill maintain."
    "INJECTED: g-a,p-b,shared")
  [ "$output" = "$(printf '%s\n' "${expect[@]}")" ]
}

@test "preload rules: budget overflow keeps project rules, lists the rest, and stays within 8000" {
  local body i out ids skipped id
  body=$(printf 'x%.0s' $(seq 1 590))
  for i in $(seq -w 1 20); do hab "$G/g-rule-$i.md" "g-rule-$i" rule "$body"; done
  for i in 1 2 3; do hab "$P/p-rule-$i.md" "p-rule-$i" rule "$body"; done
  for i in $(seq -w 1 80); do hab "$G/a-long-procedure-name-$i.md" "a-long-procedure-name-$i" procedure "Steps."; done
  run rules
  out="$output"
  [ "$(chars "$out")" -le 8000 ]
  ids=$(echo "$out" | sed -n 's/^INJECTED: //p' | tr ',' ' ')
  skipped=$(echo "$out" | sed -n 's/^Rules not loaded (budget): //p' | tr -d ',')
  [ -n "$skipped" ]
  for i in 1 2 3; do assert_contains "p-rule-$i" "$ids"; done
  for id in $ids; do assert_contains "### $id" "$out"; refute_contains " $id " " $skipped "; done
  for id in $skipped; do refute_contains "### $id" "$out"; done
  [ $(( $(echo $ids | wc -w) + $(echo $skipped | wc -w) )) -eq 23 ]
  [ "$(echo "$out" | grep -c '^### ')" -eq "$(echo $ids | wc -w)" ]
  [[ "$(echo "$out" | grep '^Procedures')" =~ \(\+[0-9]+\ more\)$ ]]
  [ "$(echo "$out" | tail -n 1 | cut -c1-10)" = "INJECTED: " ]
}

@test "preload rules: the due line ignores the throttle, and nothing prints when there is nothing to say" {
  run rules
  [ "$status" -eq 0 ] && [ -z "$output" ]
  seed_inbox "$G/inbox/claude-a.jsonl" 40 8 2
  hx "$H" "$H" watch snooze 3 >/dev/null
  run rules
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 3 ]
  [[ "$(echo "$output" | sed -n 2p)" =~ ^"habit: 40 prompts across 2 projects since ".*". Run /habit:distill."$ ]]
  [ "$(echo "$output" | tail -n 1)" = "INJECTED: " ]
}

# --- kind validation ---

# kind_md <id> <kind> <body length>: a habit with that kind and a body of x's.
kind_md() {
  printf -- '---\nid: %s\ndescription: Kind check.\nkind: %s\n---\n\n%s\n' "$1" "$2" "$(printf 'x%.0s' $(seq 1 "$3"))"
}

@test "write-habit takes a rule body up to 600 characters and rejects a longer one or an unknown kind" {
  run hx "$H" "$H" write-habit global short-rule "$(kind_md short-rule rule 600)"
  assert_contains "OK wrote" "$output"
  run hx "$H" "$H" write-habit global long-rule "$(kind_md long-rule rule 601)"
  [ "$status" -ne 0 ]
  assert_contains "Rule long-rule body is 601 characters; a rule body must be at most 600" "$output"
  [ ! -f "$G/long-rule.md" ]
  run hx "$H" "$H" write-habit global long-proc "$(kind_md long-proc procedure 2000)"
  assert_contains "OK wrote" "$output"
  run hx "$H" "$H" write-habit global odd-kind "$(kind_md odd-kind standing 10)"
  [ "$status" -ne 0 ]
  assert_contains "Invalid kind 'standing' for odd-kind: use rule or procedure" "$output"
  [ ! -f "$G/odd-kind.md" ]
}

@test "read-index active carries kind when the frontmatter has it" {
  hab "$G/a-rule.md" a-rule rule "Rule."
  hab "$G/a-proc.md" a-proc "" "Steps."
  run hx "$H" "$H" read-index merged active
  [ "$(echo "$output" | jq -c '.entries[] | select(.id=="a-rule") | keys')" = '["description","id","kind","scope","tags"]' ]
  [ "$(echo "$output" | jq -r '.entries[] | select(.id=="a-rule") | .kind')" = rule ]
  [ "$(echo "$output" | jq -r '.entries[] | select(.id=="a-proc") | has("kind")')" = false ]
}

# --- session-start ---

ssj() { # ssj <payload>: the session-start hook run from $H
  (cd "$H" && printf '%s' "$1" | env -u CLAUDE_PLUGIN_ROOT -u CURSOR_PLUGIN_ROOT HOME="$H" bash "$HOOK" session-start)
}

@test "session-start: rules only, as additionalContext in one object" {
  local expect
  hab "$G/r1.md" r1 rule "Rule one."
  hab "$P/p1.md" p1 procedure "Steps."
  expect=$(rules)
  run ssj "{\"session_id\":\"s1\",\"source\":\"startup\",\"cwd\":\"$REPO\"}"
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(jq -c 'keys' <<< "$output")" = '["hookSpecificOutput"]' ]
  [ "$(jq -r .hookSpecificOutput.hookEventName <<< "$output")" = SessionStart ]
  [ "$(jq -r .hookSpecificOutput.additionalContext <<< "$output")" = "$expect" ]
  [ ! -e "$G/nudge.next" ]
}

@test "session-start: rules plus the notice, and resume keeps only the notice" {
  local ctx
  hab "$G/r1.md" r1 rule "Rule one."
  seed_inbox "$G/inbox/claude-a.jsonl" 300 0
  run ssj '{"session_id":"s1","source":"startup"}'
  [[ "$(jq -r .systemMessage <<< "$output")" =~ ^"habit: 300 prompts" ]]
  ctx=$(jq -r .hookSpecificOutput.additionalContext <<< "$output")
  assert_contains "$(printf '### r1\nRule one.')" "$ctx"
  [[ "$(echo "$ctx" | tail -n 1)" =~ ^"habit has 300 captured prompts waiting. Mention once" ]]
  [ -s "$G/nudge.next" ]
  rm -f "$G/nudge.next"
  run ssj '{"session_id":"s1","source":"resume"}'
  jq -e .systemMessage <<< "$output" >/dev/null
  ctx=$(jq -r .hookSpecificOutput.additionalContext <<< "$output")
  refute_contains "### r1" "$ctx"
  [ "$(echo "$ctx" | wc -l | tr -d ' ')" -eq 1 ]
  run ssj '{"session_id":"s1","source":"resume"}'
  [ -z "$output" ]
}

@test "session-start: Cursor prints nothing, and nothing prints without habits or a due backlog" {
  run ssj '{"session_id":"s1","source":"startup"}'
  [ -z "$output" ]
  hab "$G/r1.md" r1 rule "Rule one."
  seed_inbox "$G/inbox/cursor-c.jsonl" 300 0
  run ssj '{"conversation_id":"c1","cursor_version":"3.25"}'
  [ -z "$output" ] && [ ! -e "$G/nudge.next" ]
}

# --- context files ---

@test "context-files caps each file, derives the memory slug, and skips missing files" {
  local root slug out
  root="$(cd "$H" && pwd -P)/my.repo"
  mkdir -p "$root/.claude/habits" "$root/sub"
  slug=$(printf '%s' "$root" | sed 's/[^A-Za-z0-9]/-/g')
  printf 'g%.0s' $(seq 1 4500) > "$H/.claude/CLAUDE.md"
  echo "Project rules here." > "$root/CLAUDE.md"
  mkdir -p "$H/.claude/projects/$slug/memory"
  echo "- [No dashes](x.md)" > "$H/.claude/projects/$slug/memory/MEMORY.md"
  run hx "$H" "$root/sub" context-files
  out="$output"
  [ "$(echo "$out" | grep '^---FILE:')" = "$(printf -- '---FILE:%s---\n---FILE:%s---\n---FILE:%s---' \
    "$H/.claude/CLAUDE.md" "$root/CLAUDE.md" "$H/.claude/projects/$slug/memory/MEMORY.md")" ]
  [ "$(echo "$out" | sed -n 2p | tr -d '\n' | wc -c | tr -d ' ')" -eq 4000 ]
  assert_contains "[truncated at 4000 characters]" "$out"
  assert_contains "Project rules here." "$out"
  refute_contains "AGENTS.md" "$out"
  [ "$(hx "$H" "$H" context-files "$root")" = "$out" ]
  run hx "$H" "$root/sub" preload distill
  assert_contains "$(printf -- '===CONTEXT===\n---FILE:%s---' "$H/.claude/CLAUDE.md")" "$output"
}
