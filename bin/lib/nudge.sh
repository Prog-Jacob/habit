# nudge.sh: The distill due rule and its throttled notices. nudge.next holds
# the epoch before which no notice is shown (after a notice, or a snooze).

NUDGE_FLOOR=30
NUDGE_FULL=300
NUDGE_AGE=604800

# due_check: sets DUE_BACKLOG (inbox lines), DUE_PROJECTS (distinct cwd),
# DUE_OLDEST (epoch, 0 when unknown) and DUE_SINCE ("Oct 4"). Returns 0 when
# distill is due. Inbox files are append-only in time order, so the oldest
# prompt is the earliest first line; mtimes would lie for backfill files.
due_check() {
  local f files=() stats now
  DUE_BACKLOG=0 DUE_PROJECTS=0 DUE_OLDEST=0 DUE_SINCE=""
  while IFS= read -r f; do files+=("$f"); done < <(inbox_files)
  [ ${#files[@]} -gt 0 ] || return 1
  stats=$(jq -nrR '
    reduce inputs as $l ({n: 0, cwd: {}, first: [], file: null};
      .n += 1 | ($l | fromjson? // null) as $o
      | if ($o | type) == "object" then .cwd[$o.cwd // "" | tostring] = 1 else . end
      | if input_filename != .file then .file = input_filename | .first += [$o.ts?] else . end)
    | ([.first[] | strings | fromdateiso8601?] | min // 0) as $old
    | "\(.n)\t\(.cwd | length)\t\($old)\t"
      + (if $old > 0 then $old | strflocaltime("%b %d") | sub(" 0"; " ") else "" end)' \
    "${files[@]}" 2>/dev/null) || return 1
  IFS=$'\t' read -r DUE_BACKLOG DUE_PROJECTS DUE_OLDEST DUE_SINCE <<< "$stats"
  [ "${DUE_BACKLOG:-0}" -ge "$NUDGE_FLOOR" ] || return 1
  [ "$DUE_BACKLOG" -ge "$NUDGE_FULL" ] && return 0
  now=$(date +%s)
  [ "${DUE_OLDEST:-0}" -gt 0 ] && [ $((now - DUE_OLDEST)) -ge "$NUDGE_AGE" ]
}

# The epoch in nudge.next, or nothing when absent or malformed.
nudge_next() {
  local next
  next=$(cat "$GLOBAL_DIR/nudge.next" 2>/dev/null) || return 1
  case "$next" in ''|*[!0-9]*) return 1 ;; esac
  echo "$next"
}

nudge_throttled() {
  local next
  next=$(nudge_next) || return 1
  [ "$next" -gt "$(date +%s)" ]
}

# nudge_set_next <seconds>: no notice before now + <seconds>. Prints the epoch.
nudge_set_next() {
  local next
  next=$(( $(date +%s) + $1 ))
  mkdir -p "$GLOBAL_DIR"
  echo "$next" | atomic_write_file "$GLOBAL_DIR/nudge.next" && echo "$next"
}

_nudge_text() {
  local noun=projects
  [ "$DUE_PROJECTS" = 1 ] && noun=project
  printf 'habit: %s prompts across %s %s since %s. Run /habit:distill.' \
    "$DUE_BACKLOG" "$DUE_PROJECTS" "$noun" "${DUE_SINCE:-?}"
}

# nudge_emit <jq filter over $m (user text) and $n (prompt count)>: print one
# JSON notice and set the 24h throttle when distill is due and not throttled.
nudge_emit() {
  local out
  nudge_throttled && return 0
  due_check || return 0
  out=$(jq -nc --arg m "$(_nudge_text)" --arg n "$DUE_BACKLOG" "$1") || return 0
  nudge_set_next 86400 >/dev/null || return 0
  printf '%s\n' "$out"
}

# session_start_json <rules> <notice or empty>: the one Claude SessionStart
# object. additionalContext holds the rules and, with a notice, one line so
# Desktop and IDE sessions, where systemMessage does not show, still hear it.
session_start_json() {
  jq -nc --arg r "$1" --arg m "$2" --arg n "${DUE_BACKLOG:-0}" '
    {hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: ([$r,
      (if $m != "" then "habit has \($n) captured prompts waiting. Mention once, briefly, that /habit:distill processes them." else empty end)]
      | map(select(. != "")) | join("\n"))}}
    + (if $m != "" then {systemMessage: $m} else {} end)'
}

# Cursor preCompact: user_message is shown to the user.
cmd_pre_compact() {
  [ -t 0 ] || cat >/dev/null 2>&1 || true
  nudge_emit '{user_message: $m}'
}
