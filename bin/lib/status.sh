# status.sh: One health report for the watch skill and the CLI. Prints every
# section, then returns 1 when an integrity check failed.

# Epoch mtime of a file (GNU stat, then BSD stat).
_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

_shim_target() {
  [ -f "$GLOBAL_DIR/bin/habit-tools.sh" ] || return 0
  sed -n 's/^exec bash "\(.*\)" "\$@"$/\1/p' "$GLOBAL_DIR/bin/habit-tools.sh" 2>/dev/null | head -n 1
}

_manifest_version() {
  local m="$1/.claude-plugin/plugin.json"
  [ -f "$m" ] || m="$1/.cursor-plugin/plugin.json"
  jq -r '.version // "?"' "$m" 2>/dev/null || echo "?"
}

# Installed habit copies, one "<host>\t<name>\t<version>" line each. Claude
# Code's install record is the source of truth: version dirs in its cache are
# leftovers or folder-install snapshots, not separate installs.
_status_copies() {
  local f
  jq -r '(.plugins // {}) | to_entries[] | select(.key | startswith("habit@"))
    | .key as $k | .value[]? | "claude\t\($k)\t\(.version // "?")"' \
    "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null
  [ -d "$HOME/.cursor" ] || return 0
  find "$HOME/.cursor" -maxdepth 7 \( -name node_modules -o -name extensions \) -prune \
      -o -path '*/.cursor-plugin/plugin.json' -print 2>/dev/null | while IFS= read -r f; do
    if [ "$(jq -r '.name // empty' "$f" 2>/dev/null)" = habit ]; then
      printf 'cursor\t%s\t%s\n' "$(cd "$(dirname "$f")/.." && pwd -P)" "$(_manifest_version "$(dirname "$f")/..")"
    fi
  done
}

# Running copy, shim target, and every installed copy.
_status_install() {
  local root target copies n host name version
  root=$(cd "$SCRIPT_DIR/.." && pwd -P)
  echo "Version: $(_manifest_version "$root") running from $root"
  target=$(_shim_target)
  echo "Shim: ${target:-missing}"
  copies=$(_status_copies | sort -u)
  echo "Installed copies:"
  if [ -z "$copies" ]; then echo "  none found"; return 0; fi
  while IFS=$'\t' read -r host name version; do
    echo "  $host $name $version"
  done <<< "$copies"
  n=$(printf '%s\n' "$copies" | wc -l | tr -d ' ')
  if [ "$n" -gt 1 ]; then
    echo "WARN: $n installed copies. One install per machine is enough: install in Claude Code only, Cursor imports it."
  fi
}

# A v2 copy still writing, or the v2 files that are safe to delete.
_status_v2() {
  local g="$GLOBAL_DIR" f left=""
  [ -f "$g/.v3" ] || return 0
  if [ -f "$g/settings.local.json" ] && [ "$g/settings.local.json" -nt "$g/.v3" ]; then
    echo "WARN: v2 code is still writing settings.local.json. Restart sessions opened before the upgrade, and uninstall any old copy."
    return 0
  fi
  for f in settings.local.json current sessions.d .pending-distill _meta.json; do
    if [ -e "$g/$f" ]; then left="$left $f"; fi
  done
  if [ -n "$left" ]; then echo "v2 leftovers you can delete from $g:$left"; fi
}

# Capture state, then the newest capture file per host (backfill excluded).
_status_capture() {
  local until host f newest files out=""
  until=$(_paused_until) || until=""
  if [ -n "$until" ]; then echo "Capture: PAUSED until $(_local_time "$until")"; else echo "Capture: ACTIVE"; fi
  for host in claude cursor; do
    files=()
    for f in "$GLOBAL_DIR"/inbox/"$host"-*.jsonl "$GLOBAL_DIR"/inbox/.claimed/*/"$host"-*.jsonl \
        "$GLOBAL_DIR"/inbox/.done/*/"$host"-*.jsonl; do
      case "$f" in *-backfill-*) continue ;; esac
      if [ -f "$f" ]; then files+=("$f"); fi
    done
    newest="none"
    if [ ${#files[@]} -gt 0 ]; then
      f=$(ls -t "${files[@]}" | head -n 1)
      newest=$(_local_time "$(_mtime "$f")")
    fi
    out="$out${out:+, }$host $newest"
  done
  echo "Last capture: $out"
}

_status_backlog() {
  local due="not due" oldest="none" next
  if due_check; then due="due"; fi
  if [ "${DUE_OLDEST:-0}" -gt 0 ]; then oldest=$(_local_time "$DUE_OLDEST" | cut -c1-10); fi
  echo "Backlog: ${DUE_BACKLOG:-0} prompts, oldest $oldest"
  if next=$(nudge_next) && [ "$next" -gt "$(date +%s)" ]; then
    due="$due (reminders snoozed until $(_local_time "$next"))"
  fi
  echo "Distill: $due"
}

_status_last_distill() {
  local run epoch
  run=$(snapshot_runs | grep -v -e '^undo-' -e '^migrate-' | tail -n 1 || true)
  if [ -z "$run" ]; then echo "Last distill: never"; return 0; fi
  epoch=$(jq -rn --arg r "$run" '$r | strptime("%Y%m%dT%H%M%SZ") | mktime' 2>/dev/null) || epoch=""
  echo "Last distill: ${epoch:+$(_local_time "$epoch") }($run)"
}

# Habit counts over global and project files, and the rule budget.
_status_habits() {
  local pdir rows p chars=0
  pdir=$(project_dir) || pdir=""
  rows=$(_index_rows "$pdir")
  jq -nr --arg rows "$rows" "$INDEX_JQ_DEFS"'
    [rows] as $all | ($all | map(select(valid))) as $v
    | ($v | map(select(.archived != "true"))) as $act
    | "Habits: \($act | length) active, \($v | length - ($act | length)) archived, "
      + "\($act | map(select(.kind == "")) | length) unclassified, \($all | length - ($v | length)) invalid"'
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    chars=$((chars + $(awk 'n >= 2 { print } /^---$/ { n++ }' "$p" | wc -m)))
  done < <(jq -nr --arg rows "$rows" "$INDEX_JQ_DEFS"'rows | select(valid and .archived != "true" and .kind == "rule") | .path')
  echo "Rule budget: $chars/$RULES_BUDGET chars"
}

_status_learnings() {
  local list
  list=$(cmd_list_learnings)
  if [ -z "$list" ]; then echo "Learnings: none"; return 0; fi
  echo "Learnings:"
  printf '%s\n' "$list" | sed 's/^/  /'
  echo "  Forget one with: watch forget <n>"
}

# Inbox files holding a line that is not valid JSON.
_status_torn() {
  local f files=()
  while IFS= read -r f; do files+=("$f"); done < <(inbox_files)
  [ ${#files[@]} -gt 0 ] || return 0
  jq -nrR 'inputs | select(try (fromjson | false) catch true) | input_filename' "${files[@]}" | sort -u
}

_status_integrity() {
  local fail=0 target bad
  target=$(_shim_target)
  if [ -z "$target" ] || [ ! -f "$target" ]; then
    echo "FAIL: the shim target is missing. Start a new session to rewrite it."; fail=1
  fi
  if [ ! -f "$GLOBAL_DIR/.v3" ]; then echo "FAIL: .v3 is missing. Run: habit-tools.sh migrate"; fail=1; fi
  bad=$(cmd_invalid_habits)
  if [ -n "$bad" ]; then echo "FAIL: invalid habit files:"; printf '%s\n' "$bad" | sed 's/^/  /'; fail=1; fi
  bad=$(_status_torn)
  if [ -n "$bad" ]; then echo "FAIL: torn lines in inbox files:"; printf '%s\n' "$bad" | sed 's/^/  /'; fail=1; fi
  if [ "$fail" -eq 0 ]; then echo "Integrity: OK"; fi
  return "$fail"
}

# Each section runs guarded, so one failing read never hides the rest.
cmd_status() {
  _status_install || true
  _status_v2 || true
  _status_capture || true
  _status_backlog || true
  _status_last_distill || true
  _status_habits || true
  _status_learnings || true
  _status_integrity || return 1
}
