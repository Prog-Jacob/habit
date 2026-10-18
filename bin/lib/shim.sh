# shim.sh: SessionStart hook: the fixed CLI path, migrate-if-needed, rules, the nudge.

# Exit 0 when version $1 is malformed or not newer than $2 (X.Y.Z, numeric).
_version_le() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    if (a !~ /^[0-9]+\.[0-9]+\.[0-9]+$/) exit 0
    split(a, x, "."); split(b, y, ".")
    for (i = 1; i <= 3; i++) { if (x[i] + 0 < y[i] + 0) exit 0; if (x[i] + 0 > y[i] + 0) exit 1 }
    exit 0
  }'
}

# Write $GLOBAL_DIR/bin/habit-tools.sh pointing at this copy when the shim is
# missing, its target is gone, or it records a version no newer than ours.
# An identical shim is left alone, so a repeat SessionStart writes nothing.
write_shim() {
  local root version shim="$GLOBAL_DIR/bin/habit-tools.sh" recorded target tmp body
  root=$(cd "$SCRIPT_DIR/.." && pwd -P) || return 1
  version=$(jq -r '.version // empty' "$root/.claude-plugin/plugin.json" 2>/dev/null) || version=""
  [ -n "$version" ] || return 0
  body=$(printf '#!/bin/bash\n# habit-shim %s\nexec bash "%s" "$@"' "$version" "$root/bin/habit-tools.sh")
  if [ -f "$shim" ]; then
    [ "$(cat "$shim")" = "$body" ] && return 0
    recorded=$(sed -n 's/^# habit-shim //p' "$shim" | head -n 1)
    target=$(sed -n 's/^exec bash "\(.*\)" "\$@"$/\1/p' "$shim" | head -n 1)
    [ -n "$target" ] && [ -f "$target" ] && ! _version_le "$recorded" "$version" && return 0
  fi
  mkdir -p "$GLOBAL_DIR/bin"
  tmp=$(mktemp "$GLOBAL_DIR/bin/.habit-tools.sh.XXXXXX") || return 1
  if printf '%s\n' "$body" > "$tmp" && chmod 755 "$tmp" && mv "$tmp" "$shim"; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# stdout is the host's hook output: only one JSON object may reach it, with the
# rules context and the throttled distill notice. A resumed session already
# holds the rules. Cursor reads its rules through rules/habit.mdc and gets its
# notice from preCompact, so it prints nothing here.
cmd_session_start() {
  local input="" re_cwd='"cwd"[[:space:]]*:[[:space:]]*"([^"\\]*)"'
  local re_resume='"source"[[:space:]]*:[[:space:]]*"resume"' resume="" due="" rules="" notice=""
  [ -t 0 ] || input=$(cat 2>/dev/null) || input=""
  if [[ $input =~ $re_cwd ]] && [ -d "${BASH_REMATCH[1]}" ]; then cd "${BASH_REMATCH[1]}" || true; fi
  write_shim >/dev/null 2>&1 || true
  migrate_if_needed bg >/dev/null 2>&1 || true
  case "$input" in *'"cursor_version"'*) return 0 ;; esac
  if [[ $input =~ $re_resume ]]; then resume=1; fi
  if [ -n "$resume" ] && nudge_throttled; then return 0; fi
  if due_check; then due=$(_nudge_text); fi
  if [ -z "$resume" ]; then rules=$(rules_render "$due" 2>/dev/null) || rules=""; fi
  if [ -n "$due" ] && ! nudge_throttled && nudge_set_next 86400 >/dev/null; then notice="$due"; fi
  [ -n "$rules$notice" ] || return 0
  session_start_json "$rules" "$notice" || true
}
