# inbox.sh: Distill runs over the inbox: claim, finish, undo.

# Move <src> into <dir>, adding a numeric suffix on a name clash.
_claim_mv() {
  local base n=1 dest
  base=$(basename "$1" .jsonl)
  dest="$2/$base.jsonl"
  while [ -e "$dest" ]; do n=$((n + 1)); dest="$2/$base.$n.jsonl"; done
  mv "$1" "$dest"
}

# Claim order: leftover claimed runs first, then the inbox, oldest first.
_claim_candidates() {
  local f
  for f in "$GLOBAL_DIR"/inbox/.claimed/*/*.jsonl; do
    if [ -f "$f" ]; then echo "$f"; fi
  done
  (cd "$GLOBAL_DIR/inbox" 2>/dev/null && ls -tr -- *.jsonl 2>/dev/null) | while IFS= read -r f; do
    echo "$GLOBAL_DIR/inbox/$f"
  done
}

# Map each claimed cwd to its project root ("" for global) as one JSON object.
_claim_project_map() {
  local cwd root
  while IFS= read -r cwd; do
    root=""
    if [ -n "$cwd" ]; then root=$(project_root "$cwd") || root=""; fi
    printf '%s\t%s\n' "$cwd" "$root"
  done | jq -nR '[inputs | split("\t") | {(.[0]): (.[1] // "")}] | add // {}'
}

cmd_claim() {
  local inbox="$GLOBAL_DIR/inbox" run dest f n total=0 moved=0
  umask 077
  run=$(new_run_id)
  dest="$inbox/.claimed/$run"
  while IFS= read -r f; do
    [ "$total" -ge "$INBOX_CAP" ] && break
    [ -f "$f" ] || continue
    mkdir -p "$dest"
    n=$(wc -l < "$f" | tr -d ' ')
    _claim_mv "$f" "$dest"
    total=$((total + n)); moved=$((moved + 1))
  done < <(_claim_candidates)
  [ "$moved" -gt 0 ] || { echo "EMPTY"; return 0; }
  for f in "$inbox"/.claimed/*/; do rmdir "$f" 2>/dev/null || true; done
  sleep 1
  local lines map dirs=("$GLOBAL_DIR") root left=0
  if root=$(project_root); then dirs+=("$root/.claude/habits"); fi
  lines=$(cat "$dest"/*.jsonl | jq -cR 'fromjson? | select(type == "object" and (.prompt | type) == "string")')
  map=$(printf '%s\n' "$lines" | jq -r '.cwd // ""' 2>/dev/null | sort -u | _claim_project_map)
  while IFS= read -r root; do
    dirs+=("$root/.claude/habits")
  done < <(printf '%s' "$map" | jq -r '[.[] | select(. != "")] | unique | .[]')
  snapshot_create "$run" "${dirs[@]}"
  echo "RUN $run"
  while IFS= read -r f; do
    case "$f" in "$dest"/*) ;; *) left=$((left + $(wc -l < "$f"))) ;; esac
  done < <(inbox_files)
  if [ "$left" -gt 0 ]; then echo "REMAINING $left"; fi
  printf '%s\n' "$lines" | jq -nr --argjson map "$map" '
    [inputs | . + {proj: ($map[.cwd // ""] // "")}] | group_by(.proj)[]
    | "---PROJECT:\(.[0].proj | if . == "" then "global" else . end)---",
      (sort_by(.ts)[] | "[\(.ts) \(.host) \(.sid | tostring | .[0:8])] \(.prompt | gsub("\n"; "\n  "))"
        + (if (.ctx // "") != "" then "\n  ctx: \(.ctx | gsub("\\s+"; " "))" else "" end))'
}

# Delete log month files older than six months.
_prune_log_months() {
  local cutoff f name
  cutoff=$(date -u +%Y-%m | awk -F- '{ m = $1 * 12 + $2 - 1 - 6; printf "%04d-%02d", int(m / 12), m % 12 + 1 }')
  for f in "$GLOBAL_DIR"/log/*.jsonl; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .jsonl)
    if [[ "$name" < "$cutoff" ]]; then rm -f "$f"; fi
  done
}

cmd_finish() {
  local run="${1:?run required}" inbox="$GLOBAL_DIR/inbox"
  [ -d "$inbox/.claimed/$run" ] || { echo "No claimed run: $run" >&2; exit 1; }
  mkdir -p "$inbox/.done"
  mv "$inbox/.claimed/$run" "$inbox/.done/$run"
  find "$inbox/.done" -mindepth 1 -maxdepth 1 -mtime +90 -exec rm -rf {} + 2>/dev/null || true
  snapshot_prune 10
  _prune_log_months
  echo "OK finished $run"
}

# undo [run]: restore the newest distill run's snapshot (or <run>), after
# snapshotting the current state so the undo itself can be undone.
cmd_undo() {
  local run="${1:-}" inbox="$GLOBAL_DIR/inbox" stage d undid
  [ -n "$run" ] || run=$(snapshot_runs | grep -v -e '^undo-' -e '^migrate-' | tail -n 1 || true)
  [ -n "$run" ] || { echo "Nothing to undo"; return 0; }
  [ -f "$GLOBAL_DIR/snapshots/$run.tar.gz" ] || { echo "No snapshot: $run" >&2; exit 1; }
  stage=$(snapshot_extract "$run") || { echo "Cannot read snapshot: $run" >&2; exit 1; }
  local dirs=("$GLOBAL_DIR") SNAP_UNDID=""
  while IFS= read -r d; do dirs+=("$d"); done < "$stage/DIRS"
  [ -d "$inbox/.done/$run" ] && SNAP_UNDID="$run"
  snapshot_create "$(new_run_id undo-)" "${dirs[@]}"
  echo "UNDO $run"
  snapshot_restore "$stage"
  if [ -n "$SNAP_UNDID" ]; then
    mkdir -p "$inbox/.claimed"
    mv "$inbox/.done/$run" "$inbox/.claimed/$run" && echo "requeued $inbox/.claimed/$run"
  fi
  undid=$(cat "$stage/UNDID" 2>/dev/null || true)
  if [ -n "$undid" ] && [ -d "$inbox/.claimed/$undid" ]; then
    mkdir -p "$inbox/.done"
    mv "$inbox/.claimed/$undid" "$inbox/.done/$undid" && echo "finished $inbox/.done/$undid"
  fi
  rm -rf "$stage"
}
