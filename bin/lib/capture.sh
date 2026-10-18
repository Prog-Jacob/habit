# capture.sh: Prompt hook capture into inbox/<host>-<sid>.jsonl.

# Shared by capture and the history backfill: slash stripping, the word
# floor, redaction, and the line size cap.
CAPTURE_JQ_DEFS='
def strip_cmds: if test("^\\s*/[A-Za-z0-9_-]+(:[A-Za-z0-9_-]+)?(\\s|$)")
  then sub("^\\s*/[A-Za-z0-9_-]+(:[A-Za-z0-9_-]+)?"; "") | strip_cmds
  else gsub("^\\s+|\\s+$"; "") end;
def words: [splits("\\s+") | select(length > 0)] | length;
def redact:
  gsub("-----BEGIN[^-]*-----[\\s\\S]*?-----END[^-]*-----"; "[redacted]")
  | gsub("\\bsk-[A-Za-z0-9_-]{16,}"; "[redacted]")
  | gsub("ghp_[A-Za-z0-9]{20,}"; "[redacted]")
  | gsub("github_pat_[A-Za-z0-9_]{20,}"; "[redacted]")
  | gsub("xox[abprs]-[A-Za-z0-9-]{10,}"; "[redacted]")
  | gsub("AKIA[0-9A-Z]{16}"; "[redacted]")
  | gsub("(?<k>password|secret|token)=\\S+"; "\(.k)=[redacted]");
def fit: .prompt |= .[0:3500]
  | until((tojson | utf8bytelength) < 4000 or .prompt == "";
      (tojson | utf8bytelength) as $n
      | .prompt |= .[0:(length - ([(($n - 3999) / 6 | ceil), 1] | max))])
  | select((tojson | utf8bytelength) < 4000);
'

# Last assistant text in the transcript tail (its final 1000 chars). Best effort.
_capture_ctx() {
  tail -c 65536 "$1" 2>/dev/null | jq -nrR '
    [inputs | fromjson? | select(type == "object")
     | select(.type == "assistant" or .role == "assistant")
     | (.message.content // .content)
     | if type == "string" then .
       elif type == "array" then [.[] | select(type == "object" and .type == "text") | .text] | join("\n")
       else empty end
     | select(test("\\S"))] | last // empty | gsub("^\\s+|\\s+$"; "") | .[-1000:]' 2>/dev/null
}

cmd_capture() {
  local input meta sid host tp words ctx="" line until
  input=$(cat) || return 0
  until=$(epoch_from "$GLOBAL_DIR/paused") && [ "$until" -gt "$(date +%s)" ] && return 0
  meta=$(printf '%s' "$input" | jq -r "$CAPTURE_JQ_DEFS"'
    [((.session_id // .conversation_id // "") | tostring | gsub("[^A-Za-z0-9_-]"; "")),
     (if has("cursor_version") then "cursor" else "claude" end),
     (.transcript_path // "" | gsub("[\\t\\n]"; "")),
     ((.prompt // "") | strip_cmds | words | tostring)] | join("\u001f")' 2>/dev/null) || return 0
  IFS=$'\x1f' read -r sid host tp words <<< "$meta"
  [ -n "$sid" ] && [ "${words:-0}" -ge 3 ] || return 0
  if [ "$words" -lt 25 ] && [ -n "$tp" ] && [ -f "$tp" ] && [ -r "$tp" ]; then
    ctx=$(_capture_ctx "$tp") || ctx=""
  fi
  line=$(printf '%s' "$input" | jq -c --arg host "$host" --arg ctx "$ctx" "$CAPTURE_JQ_DEFS"'
    {ts: (now | todate), host: $host, sid: ((.session_id // .conversation_id) | tostring),
     cwd: (.cwd // .workspace_roots[0] // ""), prompt: (.prompt | strip_cmds | redact)}
    + (if $ctx != "" then {ctx: ($ctx | redact | .[-300:] | sub("^\\s+"; ""))} else {} end)
    | fit' 2>/dev/null) || return 0
  [ -n "$line" ] || return 0
  umask 077
  mkdir -p "$GLOBAL_DIR/inbox" || return 0
  printf '%s\n' "$line" >> "$GLOBAL_DIR/inbox/$host-$sid.jsonl" || true
}
