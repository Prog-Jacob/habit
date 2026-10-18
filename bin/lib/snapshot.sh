# snapshot.sh: snapshots/<run>.tar.gz of habit files and learnings, for undo.
# Layout inside the tarball: DIRS (covered dirs), MANIFEST (absolute *.md paths
# that existed), optional UNDID (run an undo re-queued), optional LABEL, and
# root/<abs path> copies.

SNAP_DIR_NAME="snapshots"

# UTC run id; waits a second when <prefix><id> is already taken.
new_run_id() {
  local prefix="${1:-}" id
  while :; do
    id="$prefix$(date -u +%Y%m%dT%H%M%SZ)"
    [ -e "$GLOBAL_DIR/$SNAP_DIR_NAME/$id.tar.gz" ] || [ -e "$GLOBAL_DIR/inbox/.claimed/$id" ] \
      || [ -e "$GLOBAL_DIR/inbox/.done/$id" ] || { echo "$id"; return 0; }
    sleep 1
  done
}

# snapshot_create <run> <dir>...  (set SNAP_UNDID to record a re-queued run,
# SNAP_LABEL to record why the snapshot was taken)
snapshot_create() {
  local run="$1" d f stage
  shift
  mkdir -p "$GLOBAL_DIR/$SNAP_DIR_NAME"
  stage=$(mktemp -d "$GLOBAL_DIR/$SNAP_DIR_NAME/.stage.XXXXXX") || return 1
  : > "$stage/DIRS"; : > "$stage/MANIFEST"
  for d in "$@"; do
    [ -d "$d" ] || continue
    grep -qxF "$d" "$stage/DIRS" && continue
    echo "$d" >> "$stage/DIRS"
    mkdir -p "$stage/root$d"
    for f in "$d"/*.md; do
      [ -f "$f" ] || continue
      cp -p "$f" "$stage/root$d/" && echo "$f" >> "$stage/MANIFEST"
    done
  done
  if [ -f "$GLOBAL_DIR/learnings.jsonl" ]; then
    mkdir -p "$stage/root$GLOBAL_DIR"
    cp -p "$GLOBAL_DIR/learnings.jsonl" "$stage/root$GLOBAL_DIR/"
  fi
  if [ -n "${SNAP_UNDID:-}" ]; then echo "$SNAP_UNDID" > "$stage/UNDID"; fi
  if [ -n "${SNAP_LABEL:-}" ]; then echo "$SNAP_LABEL" > "$stage/LABEL"; fi
  local rc=0
  tar -czf "$GLOBAL_DIR/$SNAP_DIR_NAME/$run.tar.gz" -C "$stage" . || rc=1
  rm -rf "$stage"
  return $rc
}

# Extract a snapshot into a fresh stage dir and print its path.
snapshot_extract() {
  local stage
  stage=$(mktemp -d "$GLOBAL_DIR/$SNAP_DIR_NAME/.stage.XXXXXX") || return 1
  tar -xzf "$GLOBAL_DIR/$SNAP_DIR_NAME/$1.tar.gz" -C "$stage" || { rm -rf "$stage"; return 1; }
  echo "$stage"
}

# Restore an extracted stage over the live files and print each changed path.
snapshot_restore() {
  local stage="$1" d f live
  while IFS= read -r d; do
    [ -d "$d" ] || continue
    for f in "$stage/root$d"/*.md; do
      [ -f "$f" ] || continue
      live="$d/$(basename "$f")"
      cmp -s "$f" "$live" && continue
      atomic_write_file "$live" < "$f" && echo "$live"
    done
    for live in "$d"/*.md; do
      [ -f "$live" ] || continue
      grep -qxF "$live" "$stage/MANIFEST" && continue
      rm -f "$live" && echo "$live"
    done
  done < "$stage/DIRS"
  f="$stage/root$GLOBAL_DIR/learnings.jsonl"
  live="$GLOBAL_DIR/learnings.jsonl"
  if [ -f "$f" ]; then
    cmp -s "$f" "$live" || { cat "$f" > "$live" && echo "$live"; }
  elif [ -f "$live" ]; then
    rm -f "$live" && echo "$live"
  fi
}

# Run ids of the snapshots, oldest first (ordered by their timestamp part).
snapshot_runs() {
  local f
  for f in "$GLOBAL_DIR/$SNAP_DIR_NAME"/*.tar.gz; do
    if [ -f "$f" ]; then basename "$f" .tar.gz; fi
  done | awk '{ ts = $0; sub(/^[a-z]+-/, "", ts); print ts "\t" $0 }' | sort | cut -f2
}

# Keep the newest <n> snapshots.
snapshot_prune() {
  local keep="${1:-10}" total run
  total=$(snapshot_runs | wc -l | tr -d ' ')
  [ "$total" -gt "$keep" ] || return 0
  snapshot_runs | head -n $((total - keep)) | while IFS= read -r run; do
    rm -f "$GLOBAL_DIR/$SNAP_DIR_NAME/$run.tar.gz"
  done
}

# snapshot [label]: a distill run snapshot of the global and current project
# habits without claiming the inbox, so a write-only run can still be undone.
cmd_snapshot() {
  local run dirs=("$GLOBAL_DIR") root SNAP_LABEL="${1:-}"
  if root=$(project_root); then dirs+=("$root/.claude/habits"); fi
  run=$(new_run_id)
  snapshot_create "$run" "${dirs[@]}" || { echo "Snapshot failed" >&2; exit 1; }
  snapshot_prune 10
  echo "RUN $run"
}
