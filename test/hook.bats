#!/usr/bin/env bats
# Hook adapter: session-start, capture and pre-compact route to the CLI.
# Retired v2 events from a stale host config are silent no-ops. Also the
# distill due rule and its throttled notices.

load test_helper

@test "retired and unknown hook events exit 0, print nothing, and write nothing" {
  local h ev
  h="$BATS_TEST_TMPDIR/retired"
  for ev in session-init prompt-tick session-end bogus ""; do
    run bash -c "echo '{\"session_id\":\"s\",\"prompt\":\"a prompt with plenty of words\"}' | HOME='$h' bash '$HOOK' $ev"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
  [ ! -e "$h" ]
}

@test "the hook falls back to its own plugin root when no host root is set" {
  local h
  h=$(new_home root)
  touch "$h/.claude/habits/.v3"
  printf '{"session_id":"r-1","cwd":"/w","prompt":"routed without a plugin root"}' \
    | env -u CLAUDE_PLUGIN_ROOT -u CURSOR_PLUGIN_ROOT HOME="$h" bash "$HOOK" capture
  [ "$(jq -r .prompt "$h/.claude/habits/inbox/claude-r-1.jsonl")" = "routed without a plugin root" ]
}

@test "hook configs route session-start, capture and Cursor pre-compact, with capture async on Claude" {
  run jq -r '.hooks | keys | join(",")' "$REPO_ROOT/hooks/hooks.json"
  [ "$output" = "SessionStart,UserPromptSubmit" ]
  run jq -r '.hooks.SessionStart[0].hooks[0] | [.command, (.async // false | tostring)] | join("|")' "$REPO_ROOT/hooks/hooks.json"
  [ "$output" = 'bash ${CLAUDE_PLUGIN_ROOT}/hooks/habit-hook.sh session-start|false' ]
  run jq -r '.hooks.UserPromptSubmit[0].hooks[0] | [.command, (.async | tostring)] | join("|")' "$REPO_ROOT/hooks/hooks.json"
  [ "$output" = 'bash ${CLAUDE_PLUGIN_ROOT}/hooks/habit-hook.sh capture|true' ]
  run jq -r '.hooks | to_entries | map("\(.key)=\(.value[0].command)") | join(",")' "$REPO_ROOT/hooks/hooks.cursor.json"
  [ "$output" = "sessionStart=./hooks/habit-hook.sh session-start,beforeSubmitPrompt=./hooks/habit-hook.sh capture,preCompact=./hooks/habit-hook.sh pre-compact" ]
  [ -x "$HOOK" ]
}

# --- due rule and notices ---

# due <global dir>: "due <backlog> <projects>" or "not <backlog>" from due_check.
due() {
  ( source "$REPO_ROOT/bin/lib/common.sh"; source "$REPO_ROOT/bin/lib/nudge.sh"; GLOBAL_DIR="$1"
    if due_check; then echo "due $DUE_BACKLOG $DUE_PROJECTS"; else echo "not $DUE_BACKLOG"; fi )
}

@test "due table: each clause alone, the 30 floor, and claimed runs count" {
  local g="$BATS_TEST_TMPDIR/due/.claude/habits"
  [ "$(due "$g")" = "not 0" ]
  seed_inbox "$g/inbox/claude-a.jsonl" 300 0 3
  [ "$(due "$g")" = "due 300 3" ]
  rm -rf "$g/inbox"; seed_inbox "$g/inbox/claude-a.jsonl" 299 6
  [ "$(due "$g")" = "not 299" ]
  rm -rf "$g/inbox"; seed_inbox "$g/inbox/claude-a.jsonl" 30 7
  [ "$(due "$g")" = "due 30 1" ]
  rm -rf "$g/inbox"; seed_inbox "$g/inbox/claude-a.jsonl" 29 30
  [ "$(due "$g")" = "not 29" ]
  seed_inbox "$g/inbox/.claimed/r1/claude-b.jsonl" 1 0
  [ "$(due "$g")" = "due 30 1" ]
}

@test "due takes the oldest prompt from first lines, not file mtimes" {
  local g="$BATS_TEST_TMPDIR/first/.claude/habits"
  seed_inbox "$g/inbox/claude-backfill-00.jsonl" 20 10
  seed_inbox "$g/inbox/claude-backfill-00.jsonl" 20 0
  [ "$(due "$g")" = "due 40 1" ]
  rm -rf "$g/inbox"
  seed_inbox "$g/inbox/claude-a.jsonl" 40 1
  touch -t 202001010000 "$g/inbox/claude-a.jsonl"
  [ "$(due "$g")" = "not 40" ]
}

ss() { # ss <home> <payload>: the session-start hook from <home>
  (cd "$1" && printf '%s' "$2" | env -u CLAUDE_PLUGIN_ROOT -u CURSOR_PLUGIN_ROOT HOME="$1" bash "$HOOK" session-start)
}

@test "session-start prints the due notice once for Claude and sets the 24h throttle" {
  local h g before
  h=$(new_home ssdue); g="$h/.claude/habits"
  touch "$g/.v3"
  seed_inbox "$g/inbox/claude-a.jsonl" 40 8 2
  before=$(date +%s)
  run ss "$h" '{"session_id":"s1","source":"startup"}'
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 1 ]
  run jq -r '[.systemMessage, .hookSpecificOutput.hookEventName, .hookSpecificOutput.additionalContext] | join("|")' <<< "$output"
  [[ "$output" =~ ^"habit: 40 prompts across 2 projects since "[A-Z][a-z]{2}" "[0-9]{1,2}". Run /habit:distill.|SessionStart|" ]]
  assert_contains "40 captured prompts" "$output"
  assert_contains "/habit:distill" "${output##*|}"
  [ "$(cat "$g/nudge.next")" -ge $((before + 86400)) ]
  [ "$(cat "$g/nudge.next")" -le $(( $(date +%s) + 86400 )) ]
  # Throttled: the rules context keeps its due line, but no notice and no ask.
  run ss "$h" '{"session_id":"s2","source":"startup"}'
  [ "$status" -eq 0 ]
  [ "$(jq -r 'has("systemMessage")' <<< "$output")" = false ]
  assert_contains "habit: 40 prompts across 2 projects" "$output"
  refute_contains "Mention once" "$output"
}

@test "session-start prints nothing for Cursor or when not due, and no notice when snoozed" {
  local h g
  h=$(new_home ssquiet); g="$h/.claude/habits"
  touch "$g/.v3"
  seed_inbox "$g/inbox/claude-a.jsonl" 29 30
  run ss "$h" '{"session_id":"s1"}'
  [ -z "$output" ] && [ ! -e "$g/nudge.next" ]
  seed_inbox "$g/inbox/claude-a.jsonl" 300 0
  run ss "$h" '{"conversation_id":"c1","cursor_version":"3.25"}'
  [ -z "$output" ] && [ ! -e "$g/nudge.next" ]
  (cd "$h" && HOME="$h" bash "$TOOLS" watch snooze 2) >/dev/null
  run ss "$h" '{"session_id":"s1"}'
  refute_contains "systemMessage" "$output"
  run ss "$h" '{"session_id":"s1","source":"resume"}'
  [ -z "$output" ]
  [ "$(cat "$g/nudge.next")" -gt $(( $(date +%s) + 86400 )) ]
}

@test "session-start stdout holds only the notice, even while it writes the shim and migrates" {
  local h g
  h=$(new_home ssfirst); g="$h/.claude/habits"
  echo '{"index":[],"log":[],"learnings":[{"target":"global","note":"n"}]}' > "$g/settings.local.json"
  seed_inbox "$g/inbox/claude-a.jsonl" 300 0
  run bash -c "cd '$h' && echo '{\"session_id\":\"s1\"}' | env -u CLAUDE_PLUGIN_ROOT HOME='$h' bash '$TOOLS' session-start 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 1 ]
  jq -e '.systemMessage' <<< "$output" >/dev/null
  [ -x "$g/bin/habit-tools.sh" ] && [ -f "$g/.v3" ]
  rm -f "$g/nudge.next" "$g/inbox/claude-a.jsonl"
  run bash -c "cd '$h' && echo '{}' | HOME='$h' bash '$TOOLS' session-start 2>&1"
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "pre-compact prints user_message once, and a throttled run never reaches jq" {
  local h g fake
  h=$(new_home pc); g="$h/.claude/habits"
  touch "$g/.v3"
  seed_inbox "$g/inbox/cursor-c1.jsonl" 30 9
  run bash -c "cd '$h' && echo '{\"cursor_version\":\"3.25\"}' | HOME='$h' bash '$HOOK' pre-compact"
  [ "$status" -eq 0 ]
  [ "$(jq -c 'keys' <<< "$output")" = '["user_message"]' ]
  [[ "$(jq -r .user_message <<< "$output")" =~ ^"habit: 30 prompts across 1 project since ".*". Run /habit:distill."$ ]]
  [ -s "$g/nudge.next" ]
  fake="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fake"
  printf '#!/bin/bash\necho called >> "%s/jq.calls"\nexec "%s" "$@"\n' "$fake" "$(command -v jq)" > "$fake/jq"
  chmod +x "$fake/jq"
  run bash -c "cd '$h' && echo '{}' | PATH='$fake:$PATH' HOME='$h' bash '$HOOK' pre-compact"
  [ "$status" -eq 0 ] && [ -z "$output" ]
  [ ! -e "$fake/jq.calls" ]
}
