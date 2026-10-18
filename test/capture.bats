#!/usr/bin/env bats
# Capture: payload normalisation, prompt filter, ctx tail, redaction, pause,
# file mode, size caps, and parallel appends into one session file.

load test_helper

setup() {
  H=$(new_home cap)
  touch "$H/.claude/habits/.v3"
  INBOX="$H/.claude/habits/inbox"
}

# cap <json payload>: run capture and keep its combined output in $output.
cap() {
  run bash -c "printf '%s' \"\$1\" | HOME='$H' bash '$TOOLS' capture" _ "$1"
}

payload() { # payload <sid> <prompt> [extra json fields]
  local extra="${3:-}"
  [ -n "$extra" ] || extra='{}'
  jq -nc --arg sid "$1" --arg p "$2" --argjson x "$extra" \
    '{session_id: $sid, cwd: "/w/repo", prompt: $p, hook_event_name: "UserPromptSubmit"} + $x'
}

@test "capture writes a Claude payload line and prints nothing" {
  cap "$(payload s-1 'please fix the flaky login test')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  local line
  line=$(cat "$INBOX/claude-s-1.jsonl")
  [ "$(echo "$line" | jq -r '[.host, .sid, .cwd, .prompt] | join("|")')" = "claude|s-1|/w/repo|please fix the flaky login test" ]
  echo "$line" | jq -e '.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")' >/dev/null
  echo "$line" | jq -e 'has("ctx") | not' >/dev/null
}

@test "capture reads a Cursor payload with no cwd from workspace_roots" {
  cap '{"conversation_id":"cur-9","cursor_version":"3.25.6","workspace_roots":["/w/cursor"],"prompt":"/suggest make the build faster now"}'
  [ -z "$output" ]
  [ "$(jq -r '[.host, .sid, .cwd, .prompt] | join("|")' "$INBOX/cursor-cur-9.jsonl")" = "cursor|cur-9|/w/cursor|make the build faster now" ]
}

@test "capture strips leading slash commands but keeps paths" {
  cap "$(payload s-2 '/habit:suggest /grice fix x y')"
  cap "$(payload s-2 '/tmp/out.log is empty')"
  run jq -r '.prompt' "$INBOX/claude-s-2.jsonl"
  [ "$output" = "$(printf 'fix x y\n/tmp/out.log is empty')" ]
}

@test "capture drops prompts with fewer than three words left" {
  cap "$(payload s-3 '/habit:suggest fix it')"
  cap "$(payload s-3 '/cost')"
  cap "$(payload '' 'a prompt with no session id')"
  [ ! -e "$INBOX/claude-s-3.jsonl" ]
  [ -z "$(ls "$INBOX" 2>/dev/null)" ]
}

@test "capture sanitizes the session id in the file name" {
  cap "$(payload '../e v/il' 'a prompt with an odd session id')"
  [ -f "$INBOX/claude-evil.jsonl" ]
  [ "$(jq -r .sid "$INBOX/claude-evil.jsonl")" = "../e v/il" ]
}

@test "capture truncates to 3500 codepoints and keeps multibyte lines under 4000 bytes" {
  local long
  long=$(printf 'word %.0s' $(seq 1 1000))
  cap "$(payload s-4 "$long")"
  [ "$(jq -r '.prompt | length' "$INBOX/claude-s-4.jsonl")" -eq 3500 ]
  long=$(printf 'çé€ %.0s' $(seq 1 1200))
  cap "$(payload s-5 "$long")"
  local line
  line=$(cat "$INBOX/claude-s-5.jsonl")
  [ "$(printf '%s' "$line" | wc -c | tr -d ' ')" -lt 4000 ]
  echo "$line" | jq -e '.prompt | length > 500' >/dev/null
}

@test "capture redacts every secret pattern and keeps the key of key=value" {
  local p
  p='deploy with sk-abcdefghijklmnop1234 ghp_abcdefghijklmnopqrstuvwx github_pat_abcdefghij_klmnopqrstuv'
  p="$p xoxb-1234567890-abc AKIAABCDEFGHIJKLMNOP password=hunter2 secret=s3 token=t0k"
  p="$p -----BEGIN RSA PRIVATE KEY-----
MIIEabc
-----END RSA PRIVATE KEY----- done and task-notification-handler-name stays"
  cap "$(payload s-6 "$p")"
  run jq -r .prompt "$INBOX/claude-s-6.jsonl"
  for leak in sk-abc ghp_ github_pat_ xoxb- AKIA hunter2 s3 t0k MIIE BEGIN; do
    refute_contains "$leak" "$output"
  done
  assert_contains "password=[redacted]" "$output"
  assert_contains "secret=[redacted]" "$output"
  assert_contains "token=[redacted]" "$output"
  assert_contains "task-notification-handler-name stays" "$output"
  [ "$(grep -o '\[redacted\]' <<< "$output" | wc -l | tr -d ' ')" -eq 9 ]
}

@test "capture honours an active pause and resumes after it expires" {
  echo $(( $(date +%s) + 3600 )) > "$H/.claude/habits/paused"
  cap "$(payload s-7 'this prompt is paused out')"
  [ ! -e "$INBOX/claude-s-7.jsonl" ]
  echo $(( $(date +%s) - 10 )) > "$H/.claude/habits/paused"
  cap "$(payload s-7 'this prompt is captured again')"
  [ "$(wc -l < "$INBOX/claude-s-7.jsonl" | tr -d ' ')" -eq 1 ]
}

@test "capture creates the inbox file with mode 600" {
  cap "$(payload s-8 'check the file mode please')"
  run ls -l "$INBOX/claude-s-8.jsonl"
  [ "${output:0:10}" = "-rw-------" ]
}

@test "capture takes ctx from the last assistant text in the transcript tail only" {
  local tp="$BATS_TEST_TMPDIR/t.jsonl"
  cat > "$tp" << 'JSONL'
{"type":"assistant","message":{"content":[{"type":"text","text":"Older reply."}]}}
{"type":"user","message":{"content":[{"type":"tool_result","content":"TOOL OUTPUT"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Should I also drop hyphens?"},{"type":"tool_use","name":"Bash"}]}}
{"type":"user","message":{"content":[{"type":"tool_result","content":"MORE TOOL OUTPUT"}]}}
not json at all
JSONL
  cap "$(payload s-9 'yeah no hyphens either' "{\"transcript_path\":\"$tp\"}")"
  [ "$(jq -r .ctx "$INBOX/claude-s-9.jsonl")" = "Should I also drop hyphens?" ]

  local long
  long=$(printf 'w%.0s ' $(seq 1 30))
  cap "$(payload s-10 "$long" "{\"transcript_path\":\"$tp\"}")"
  jq -e 'has("ctx") | not' "$INBOX/claude-s-10.jsonl" >/dev/null
}

@test "capture reads Cursor transcript ctx with string content and keeps 300 chars" {
  local tp="$BATS_TEST_TMPDIR/c.jsonl"
  jq -nc --arg t "$(printf 'x%.0s' $(seq 1 400))END" '{role: "assistant", message: {content: $t}}' > "$tp"
  cap "{\"conversation_id\":\"c-2\",\"cursor_version\":\"3\",\"workspace_roots\":[\"/w\"],\"prompt\":\"ok do that then\",\"transcript_path\":\"$tp\"}"
  run jq -r .ctx "$INBOX/cursor-c-2.jsonl"
  [ "${#output}" -eq 300 ]
  [ "${output: -3}" = "END" ]
}

@test "capture with a missing transcript stores no ctx" {
  cap "$(payload s-11 'short prompt here' '{"transcript_path":"/nonexistent/t.jsonl"}')"
  jq -e 'has("ctx") | not' "$INBOX/claude-s-11.jsonl" >/dev/null
}

@test "40 parallel captures into one session file produce 40 valid lines" {
  local i
  for i in $(seq 1 40); do
    payload s-par "parallel prompt number $i here" | HOME="$H" bash "$TOOLS" capture &
  done
  wait
  [ "$(wc -l < "$INBOX/claude-s-par.jsonl" | tr -d ' ')" -eq 40 ]
  [ "$(jq -c . "$INBOX/claude-s-par.jsonl" | wc -l | tr -d ' ')" -eq 40 ]
  [ "$(jq -r .prompt "$INBOX/claude-s-par.jsonl" | sort -u | wc -l | tr -d ' ')" -eq 40 ]
}

@test "hook capture passes the payload through and prints nothing" {
  run bash -c "printf '%s' '{\"session_id\":\"hk-1\",\"cwd\":\"/w\",\"prompt\":\"hook routed prompt here\"}' | HOME='$H' bash '$HOOK' capture"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(jq -r .prompt "$INBOX/claude-hk-1.jsonl")" = "hook routed prompt here" ]
}

@test "hook capture backgrounds itself for Cursor and still lands the line" {
  run bash -c "printf '%s' '{\"conversation_id\":\"hk-2\",\"cursor_version\":\"3\",\"workspace_roots\":[\"/w\"],\"prompt\":\"cursor hook prompt here\"}' | HOME='$H' bash '$HOOK' capture"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  local i
  for i in $(seq 1 50); do [ -s "$INBOX/cursor-hk-2.jsonl" ] && break; sleep 0.1; done
  [ "$(jq -r .prompt "$INBOX/cursor-hk-2.jsonl")" = "cursor hook prompt here" ]
}
