#!/usr/bin/env bats
# Hook adapter: only session-start and capture route to the CLI. Retired v2
# events from a stale host config are silent no-ops.

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

@test "hook configs route only session-start and capture, with capture async on Claude" {
  run jq -r '.hooks | keys | join(",")' "$REPO_ROOT/hooks/hooks.json"
  [ "$output" = "SessionStart,UserPromptSubmit" ]
  run jq -r '.hooks.SessionStart[0].hooks[0] | [.command, (.async // false | tostring)] | join("|")' "$REPO_ROOT/hooks/hooks.json"
  [ "$output" = 'bash ${CLAUDE_PLUGIN_ROOT}/hooks/habit-hook.sh session-start|false' ]
  run jq -r '.hooks.UserPromptSubmit[0].hooks[0] | [.command, (.async | tostring)] | join("|")' "$REPO_ROOT/hooks/hooks.json"
  [ "$output" = 'bash ${CLAUDE_PLUGIN_ROOT}/hooks/habit-hook.sh capture|true' ]
  run jq -r '.hooks | to_entries | map("\(.key)=\(.value[0].command)") | join(",")' "$REPO_ROOT/hooks/hooks.cursor.json"
  [ "$output" = "sessionStart=./hooks/habit-hook.sh session-start,beforeSubmitPrompt=./hooks/habit-hook.sh capture" ]
  [ -x "$HOOK" ]
}
