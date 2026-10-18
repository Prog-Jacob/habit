#!/usr/bin/env bats
# status (watch status): installed copies, v2 state, capture, backlog, habit
# counts, the rule budget, and integrity checks.

load test_helper

# A HOME with two Claude installs in the install record, a leftover cache dir,
# one Cursor copy, and an unrelated Cursor plugin.
seed_copies() {
  mkdir -p "$1/.claude/plugins/cache/mk/habit/2.0.0" "$1/.cursor/plugins/cache/cp/habit/abc/.cursor-plugin" \
    "$1/.cursor/plugins/cache/cp/figma/def/.cursor-plugin"
  jq -n '{plugins: {"habit@mk": [{version: "2.1.0"}], "habit@other": [{version: "2.2.0"}], "figma@mk": [{version: "1.0.0"}]}}' \
    > "$1/.claude/plugins/installed_plugins.json"
  echo '{"name":"habit","version":"2.2.0"}' > "$1/.cursor/plugins/cache/cp/habit/abc/.cursor-plugin/plugin.json"
  echo '{"name":"figma","version":"1.0.0"}' > "$1/.cursor/plugins/cache/cp/figma/def/.cursor-plugin/plugin.json"
}

@test "status flags extra copies and a v2 copy still writing, and shows each section" {
  local h g out
  h=$(new_home st); g="$h/.claude/habits"
  seed_copies "$h"
  seed_shim "$h"
  touch -t 202610010000 "$g/.v3"
  echo '{"log":[]}' > "$g/settings.local.json"
  seed_inbox "$g/inbox/claude-s1.jsonl" 10 8 2
  seed_inbox "$g/inbox/claude-backfill-00.jsonl" 5 20
  seed_inbox "$g/inbox/.done/r0/cursor-c1.jsonl" 3 9
  touch -t 202610050930 "$g/inbox/claude-s1.jsonl"
  touch -t 202610060930 "$g/inbox/.done/r0/cursor-c1.jsonl"
  _write_habit "$g/alpha.md" alpha "[a]" "Alpha habit." global false "Body text."
  printf -- '---\nid: rule-one\ndescription: A rule.\nkind: rule\narchived: false\n---\n0123456789\n' > "$g/rule-one.md"
  _write_habit "$g/gone.md" gone "[g]" "Archived." global true "G."
  mkdir -p "$g/snapshots"
  touch "$g/snapshots/migrate-20261002T000000Z.tar.gz" "$g/snapshots/20261003T101500Z.tar.gz" \
    "$g/snapshots/undo-20261004T000000Z.tar.gz"
  run hx "$h" "$h" status
  [ "$status" -eq 0 ]
  out="$output"
  assert_contains "Version: $(jq -r .version "$REPO_ROOT/.claude-plugin/plugin.json") running from $REPO_ROOT" "$out"
  assert_contains "Shim: $TOOLS" "$out"
  assert_contains "claude habit@mk 2.1.0" "$out"
  assert_contains "claude habit@other 2.2.0" "$out"
  assert_contains "/.cursor/plugins/cache/cp/habit/abc 2.2.0" "$out"
  assert_contains "  cursor /" "$out"
  refute_contains "figma" "$out"
  refute_contains "cache/mk/habit/2.0.0" "$out"
  assert_contains "WARN: 3 installed copies. One install per machine is enough" "$out"
  assert_contains "WARN: v2 code is still writing settings.local.json" "$out"
  refute_contains "v2 leftovers" "$out"
  assert_contains "Last capture: claude 2026-10-05 09:30, cursor 2026-10-06 09:30" "$out"
  assert_contains "Backlog: 15 prompts, oldest $(date -r $(( $(date +%s) - 20 * 86400 )) +%Y-%m-%d 2>/dev/null || date -d "-20 days" +%Y-%m-%d)" "$out"
  assert_contains "Distill: not due" "$out"
  assert_contains "(20261003T101500Z)" "$out"
  assert_contains "Habits: 2 active, 1 archived, 1 unclassified, 0 invalid" "$out"
  assert_contains "Rule budget: $(hx "$h" "$h" preload rules | jq -Rs length)/8000 chars" "$out"
  refute_contains "not loaded" "$out"
  assert_contains "Integrity: OK" "$out"
}

@test "status reports the rendered rule budget and how many rules did not load" {
  local h g i body rules
  h=$(new_home stb); g="$h/.claude/habits"
  seed_shim "$h"
  touch "$g/.v3"
  body=$(printf 'x%.0s' $(seq 1 590))
  for i in $(seq -w 1 20); do
    printf -- '---\nid: r-%s\ndescription: Rule.\nkind: rule\n---\n%s\n' "$i" "$body" > "$g/r-$i.md"
  done
  rules=$(hx "$h" "$h" preload rules)
  local n k
  n=$(printf '%s\n' "$rules" | jq -Rs length)
  k=$(printf '%s\n' "$rules" | sed -n 's/^Rules not loaded (budget): //p' | tr ',' '\n' | wc -l | tr -d ' ')
  [ "$n" -le 8000 ] && [ "$k" -gt 0 ]
  run hx "$h" "$h" status
  [ "$status" -eq 0 ]
  assert_contains "Rule budget: $n/8000 chars, $k rules not loaded" "$output"
}

@test "status lists v2 leftovers once no v2 copy writes" {
  local h g
  h=$(new_home stl); g="$h/.claude/habits"
  seed_shim "$h"
  mkdir -p "$g/sessions.d"
  echo '{}' > "$g/settings.local.json"
  touch "$g/_meta.json"
  touch -t 202601010000 "$g/settings.local.json"
  touch "$g/.v3"
  run hx "$h" "$h" status
  [ "$status" -eq 0 ]
  assert_contains "v2 leftovers you can delete from $g: settings.local.json sessions.d _meta.json" "$output"
  refute_contains "WARN" "$output"
}

@test "status prints every section, then exits non-zero on an integrity failure" {
  local h g
  h=$(new_home sti); g="$h/.claude/habits"
  seed_shim "$h"
  touch "$g/.v3"
  seed_inbox "$g/inbox/claude-s1.jsonl" 2 0
  printf '{"ts":"2026-10-01T00:00:00Z","prom' >> "$g/inbox/claude-s1.jsonl"
  run hx "$h" "$h" status
  [ "$status" -ne 0 ]
  assert_contains "Learnings: none" "$output"
  assert_contains "$(printf 'FAIL: torn lines in inbox files:\n  %s' "$g/inbox/claude-s1.jsonl")" "$output"
  refute_contains "Integrity: OK" "$output"
  rm -rf "$g/inbox" "$g/.v3" "$g/bin"
  printf -- '---\nid: wrong\ndescription: Bad.\n---\n' > "$g/bad.md"
  run hx "$h" "$h" status
  [ "$status" -ne 0 ]
  assert_contains "FAIL: the shim target is missing" "$output"
  assert_contains "FAIL: .v3 is missing" "$output"
  assert_contains "bad.md: id wrong does not match the filename" "$output"
  [ ! -f "$g/.v3" ]
}
