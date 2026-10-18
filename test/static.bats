#!/usr/bin/env bats
# Static checks and fitness functions (V3 plan section 9): the skill dialect,
# hook side effects, write ownership, command coverage, and manifest parity.

load test_helper

SKILLS="$REPO_ROOT/skills"
SKILL_NAMES="habit suggest edit watch distill"

# --- Skill dialect ---

@test "fitness 1: no skill file carries a plugin root, a bang preload, a subshell, or session plumbing" {
  run grep -rnF -e '${CLAUDE_PLUGIN_ROOT}' -e '$(' -e 'HABIT_BIN' -e 'HABIT_SID' -e 'sessions.d' "$SKILLS"
  [ -z "$output" ]
  run grep -rnE '^!`' "$SKILLS"
  [ -z "$output" ]
}

@test "every CLI call in skills is the literal shim path run through bash" {
  run bash -c "grep -rhoE '.{0,26}habit-tools\.sh' '$SKILLS' | grep -vxF 'bash ~/.claude/habits/bin/habit-tools.sh'"
  [ -z "$output" ]
}

@test "each skill first runs its own preload and explains a missing shim" {
  local s first bad=""
  for s in $SKILL_NAMES; do
    first=$(grep -oE 'habit-tools\.sh [a-z-]+ [a-z]+' "$SKILLS/$s/SKILL.md" | head -n 1)
    [ "$first" = "habit-tools.sh preload $s" ] || bad="$bad $s"
    grep -q "hooks have not run yet" "$SKILLS/$s/SKILL.md" || bad="$bad $s-missing"
  done
  [ -z "$bad" ]
  [ ! -e "$SKILLS/run" ]
}

@test "no skill body embeds a literal /habit: command reference" {
  run grep -rl '/habit:' "$SKILLS" --include=SKILL.md
  [ -z "$output" ]
}

@test "ambient skills omit disable-model-invocation; explicit skills set it" {
  local s bad=""
  for s in habit suggest; do
    grep -q 'disable-model-invocation: true' "$SKILLS/$s/SKILL.md" && bad="$bad $s"
  done
  for s in edit watch distill; do
    grep -q 'disable-model-invocation: true' "$SKILLS/$s/SKILL.md" || bad="$bad $s"
  done
  grep -q '^context: fork' "$SKILLS/distill/SKILL.md" || bad="$bad fork"
  [ -z "$bad" ]
}

@test "action skills carry the habit- name prefix" {
  local s bad=""
  for s in edit suggest watch distill; do
    grep -q "^name: habit-$s" "$SKILLS/$s/SKILL.md" || bad="$bad $s"
  done
  [ -z "$bad" ]
}

@test "habit and suggest log with the session id and suggest logs no note" {
  local s
  for s in habit suggest; do
    assert_contains 'log-exec' "$(cat "$SKILLS/$s/SKILL.md")"
    assert_contains '${CLAUDE_SESSION_ID}' "$(grep 'log-exec' "$SKILLS/$s/SKILL.md")"
  done
  refute_contains 'note' "$(grep "log-exec '" "$SKILLS/suggest/SKILL.md")"
  refute_contains 'override' "$(grep "log-exec '" "$SKILLS/suggest/SKILL.md")"
}

@test "watch has no learnings overlay but shows status, pauses, snoozes, and forgets learnings" {
  local body c
  body=$(cat "$SKILLS/watch/SKILL.md")
  refute_contains "===LEARNINGS===" "$body"
  refute_contains "read-learnings" "$body"
  for c in list-learnings forget-learning status "watch off" "watch on" "watch snooze"; do
    assert_contains "habit-tools.sh $c" "$body"
  done
}

@test "distill claims, finishes, undoes, writes learnings, and checks env-context" {
  local body
  body=$(cat "$SKILLS/distill/SKILL.md")
  for c in claim finish undo write-learning env-context "write-habit project"; do
    assert_contains "habit-tools.sh $c" "$body"
  done
  assert_contains "HABIT_PROJECT_DIR=<dir> bash ~/.claude/habits/bin/habit-tools.sh write-habit project" "$body"
  assert_contains "do not read or edit any plugin files" "$body"
}

# --- Fitness 2: hook side effects ---

# Every path under $1 in order, with a content checksum for files.
tree_state() {
  (cd "$1" && find . | LC_ALL=C sort | while IFS= read -r p; do
    if [ -f "$p" ]; then echo "$p $(cksum < "$p")"; else echo "$p"; fi
  done)
}

hook() { # hook <home> <cwd> <event> <payload>
  (cd "$2" && printf '%s' "$4" | env -u CLAUDE_PLUGIN_ROOT -u CURSOR_PLUGIN_ROOT HOME="$1" bash "$HOOK" "$3")
}

@test "fitness 2: hooks change only the inbox, the shim, nudge.next, and first-run migration outputs" {
  local h g repo before after changed
  h=$(new_home fit2)
  g="$h/.claude/habits"
  repo="$(cd "$h" && pwd -P)/repo"
  mkdir -p "$repo/.claude/habits"
  _write_habit "$g/alpha.md" alpha "[a]" "Alpha habit." global false "A."
  _write_habit "$repo/.claude/habits/proj.md" proj "[p]" "Project habit." project false "P."
  echo '{"index":[],"log":[{"id":"alpha","override":"","timestamp":"2026-10-01T00:00:00Z"}],"learnings":[{"target":"global","note":"n"}]}' > "$g/settings.local.json"
  echo '{"log":[{"id":"proj","override":"","timestamp":"2026-10-01T00:00:00Z"}]}' > "$repo/.claude/habits/settings.local.json"
  jq -nc '{display: "a recent typed prompt here", timestamp: ((now - 3600) * 1000 | floor), project: "/w", sessionId: "h1"}' > "$h/.claude/history.jsonl"

  before=$(tree_state "$h")
  hook "$h" "$repo" session-start '{"session_id":"s1","source":"startup"}'
  local i
  for i in $(seq 1 50); do [ -s "$g/inbox/claude-backfill-00.jsonl" ] && break; sleep 0.1; done
  sleep 0.2
  after=$(tree_state "$h")
  changed=$(LC_ALL=C comm -3 <(echo "$before") <(echo "$after") | awk '{print $1}' | sort -u)
  [ -n "$changed" ]
  run bash -c "echo '$changed' | grep -vE '^\./\.claude/habits/(bin|inbox|log|snapshots)(/|$)|^\./\.claude/habits/(\.v3|nudge\.next|learnings\.jsonl|migrated-projects|backfill-skipped)$'"
  [ -z "$output" ]
  [ -x "$g/bin/habit-tools.sh" ] && [ -f "$g/.v3" ]

  before=$(tree_state "$h")
  hook "$h" "$repo" session-start '{"session_id":"s2","source":"resume"}'
  [ "$(tree_state "$h")" = "$before" ]

  hook "$h" "$repo" capture '{"session_id":"s2","cwd":"/w","prompt":"a captured prompt goes here"}'
  changed=$(LC_ALL=C comm -3 <(echo "$before") <(tree_state "$h") | awk '{print $1}' | sort -u)
  [ "$changed" = "./.claude/habits/inbox/claude-s2.jsonl" ]

  seed_inbox "$g/inbox/claude-s2.jsonl" 300 0
  before=$(tree_state "$h")
  [ -n "$(hook "$h" "$repo" pre-compact '{"cursor_version":"3.25"}')" ]
  changed=$(LC_ALL=C comm -3 <(echo "$before") <(tree_state "$h") | awk '{print $1}' | sort -u)
  [ "$changed" = "./.claude/habits/nudge.next" ]
}

# --- Fitness 3 and 4: write ownership ---

@test "fitness 3: nothing under bin/ writes settings.local.json" {
  run grep -rnE '(>|mv |cp |tee |atomic_write_file)[^|;&]*settings\.local\.json' "$REPO_ROOT/bin"
  [ -z "$output" ]
  run grep -rnE '>>? *"?\$\{?state\b|STATE_FILE|update_state|write_state' "$REPO_ROOT/bin"
  [ -z "$output" ]
}

@test "fitness 4: mkdir of a project habits dir appears only in write-habit" {
  local rest
  # Every other mkdir targets a path rooted in the global dir.
  rest=$(grep -rn 'mkdir' "$REPO_ROOT/bin" | grep -vE 'mkdir (-p )?"\$(GLOBAL_DIR|inbox|dest|lock|stage)')
  [ "$(echo "$rest" | wc -l | tr -d ' ')" -eq 1 ]
  assert_contains "bin/lib/habit.sh:" "$rest"
  [ "$(awk '/^cmd_write_habit\(\)/{f=1} f && /^}/{f=0} f && /mkdir/' "$REPO_ROOT/bin/lib/habit.sh")" = "${rest#*:*:}" ]
}

# --- Fitness 5: command coverage ---

dispatcher_cmds() {
  awk '/^case "\$cmd" in/ { n++; f = (n == 1); next }
       f && /^esac/ { exit }
       f && /^  [a-z][a-z|-]*\)/ { sub(/\).*/, ""); gsub(/ /, ""); k = split($0, a, "|"); for (i = 1; i <= k; i++) print a[i] }' \
    "$REPO_ROOT/bin/habit-tools.sh" | sort -u
}

named_cmds() {
  { grep -rhoE 'habit-tools\.sh [a-z][a-z-]*' "$SKILLS"
    grep -rhoE 'habit-hook\.sh [a-z][a-z-]*' "$REPO_ROOT"/hooks/*.json; } | awk '{print $2}' | sort -u
}

@test "fitness 5: skills and hooks name only real commands, and every command is named" {
  # CLI-only: migrate and invalid-habits are user repair tools; read-log and
  # read-learnings are the raw reads that preload bundles, kept for debugging.
  local allow="invalid-habits migrate read-learnings read-log" c bad=""
  local have named
  have=$(dispatcher_cmds)
  named=$(named_cmds)
  [ "$(echo "$have" | wc -l | tr -d ' ')" -gt 10 ]
  for c in $named; do echo "$have" | grep -qxF "$c" || bad="$bad missing:$c"; done
  for c in $have; do
    echo "$named" | grep -qxF "$c" && continue
    case " $allow " in *" $c "*) ;; *) bad="$bad unnamed:$c" ;; esac
  done
  [ -z "$bad" ]
  grep -q 'session-start|capture|pre-compact)' "$HOOK"
}

# --- Fitness 6: manifests ---

@test "fitness 6: the two plugin manifests share a version and the cursor manifest is valid" {
  local cc cur
  cc=$(jq -r .version "$REPO_ROOT/.claude-plugin/plugin.json")
  cur=$(jq -r .version "$REPO_ROOT/.cursor-plugin/plugin.json")
  [ "$cc" = "$cur" ]
  assert_contains "./skills/" "$(jq -r .skills "$REPO_ROOT/.cursor-plugin/plugin.json")"
  assert_contains "hooks.cursor.json" "$(jq -r .hooks "$REPO_ROOT/.cursor-plugin/plugin.json")"
}
