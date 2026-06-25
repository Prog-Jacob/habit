#!/usr/bin/env bats
# Static checks over the skills and manifests: the skill dialect lint, name and
# invocation conventions, manifest parity, learnings surfacing, the distill
# lifecycle, and the friction-capture wording. These read repo files directly
# and take no fixtures.

load test_helper

SKILLS="$REPO_ROOT/skills"

# --- Skill dialect lint ---

@test "no skill uses load-time inline bash execution" {
  run grep -rl '!`' "$SKILLS" --include=SKILL.md
  [ -z "$output" ]
}

@test "no skill references CLAUDE_SESSION_ID" {
  run grep -rl 'CLAUDE_SESSION_ID' "$SKILLS" --include=SKILL.md
  [ -z "$output" ]
}

@test "no skill body embeds a literal /habit: command reference" {
  run grep -rl '/habit:' "$SKILLS" --include=SKILL.md
  [ -z "$output" ]
}

@test "every skill sources the breadcrumb and uses HABIT_BIN" {
  local bad=""
  for dir in "$SKILLS"/*/; do
    [ -f "$dir/SKILL.md" ] || continue
    if ! grep -q 'source "$HOME/.claude/habits/current"' "$dir/SKILL.md" \
      || ! grep -q 'HABIT_BIN' "$dir/SKILL.md"; then
      bad="$bad $(basename "$dir")"
    fi
  done
  [ -z "$bad" ]
}

@test "ambient skills omit disable-model-invocation; explicit skills set it" {
  local amb_bad=""
  for s in habit suggest; do
    grep -q 'disable-model-invocation: true' "$SKILLS/$s/SKILL.md" && amb_bad="$amb_bad $s"
  done
  [ -z "$amb_bad" ]
  local exp_bad=""
  for s in run edit watch distill; do
    grep -q 'disable-model-invocation: true' "$SKILLS/$s/SKILL.md" || exp_bad="$exp_bad $s"
  done
  [ -z "$exp_bad" ]
}

@test "action skills carry the habit- name prefix" {
  local bad=""
  for s in run edit suggest watch distill; do
    grep -q "^name: habit-$s" "$SKILLS/$s/SKILL.md" || bad="$bad $s"
  done
  [ -z "$bad" ]
}

# --- Manifests ---

@test "the two plugin manifests share a version and the cursor manifest is valid" {
  local cc cur
  cc=$(jq -r .version "$REPO_ROOT/.claude-plugin/plugin.json")
  cur=$(jq -r .version "$REPO_ROOT/.cursor-plugin/plugin.json")
  [ "$cc" = "$cur" ]
  assert_contains "./skills/" "$(jq -r .skills "$REPO_ROOT/.cursor-plugin/plugin.json")"
  assert_contains "hooks.cursor.json" "$(jq -r .hooks "$REPO_ROOT/.cursor-plugin/plugin.json")"
}

# --- Learnings surfacing ---

@test "every decision-surface skill reads its own learnings target" {
  local bad=""
  for pair in habit:habit run:run edit:edit suggest:suggest distill:distill; do
    local s="${pair%%:*}" tgt="${pair##*:}"
    grep -qF "read-learnings $tgt" "$SKILLS/$s/SKILL.md" || bad="$bad $s"
  done
  [ -z "$bad" ]
}

@test "watch carries no learnings call" {
  run cat "$SKILLS/watch/SKILL.md"
  refute_contains "read-learnings" "$output"
}

# --- Distill lifecycle ---

@test "distill self-improve owns learnings and the guarded observation clear" {
  local dsl="$SKILLS/distill/SKILL.md"
  local body
  body=$(cat "$dsl")
  assert_contains "write-learning" "$body"
  assert_contains "env-context" "$body"

  local cleanup_block
  cleanup_block=$(awk '/^## Cleanup/{f=1} f' "$dsl")
  refute_contains "clear-observations" "$cleanup_block"

  local selfimprove_block
  selfimprove_block=$(awk '/^## Self-improve/{f=1} /^## Cleanup/{f=0} f' "$dsl")
  assert_contains "clear-observations" "$selfimprove_block"
  assert_contains "do NOT clear" "$selfimprove_block"
  assert_contains "do not read or edit any plugin files" "$selfimprove_block"
}

@test "every distill branch reaches Self-improve and Restructure prunes learnings" {
  local dsl="$SKILLS/distill/SKILL.md"
  assert_contains "Self-improve" "$(awk '/^## Regular/{f=1} /^---/{if(f)f=0} f' "$dsl")"
  assert_contains "Self-improve" "$(awk '/^## Maintain/{f=1} /^## Regular/{f=0} f' "$dsl")"
  assert_contains "Self-improve" "$(awk '/^## Project/{f=1} /^## Maintain/{f=0} f' "$dsl")"
  assert_contains "prune-learnings" "$(awk '/^## Restructure/{f=1} /^## Self-improve/{f=0} f' "$dsl")"
}

# --- Friction capture ---

@test "run and suggest log only narrow friction" {
  local run_skill sug_skill
  run_skill=$(cat "$SKILLS/run/SKILL.md")
  assert_contains "log-observation" "$run_skill"
  assert_contains "appears to have meant" "$run_skill"
  assert_contains "requires a missing" "$run_skill"

  sug_skill=$(cat "$SKILLS/suggest/SKILL.md")
  assert_contains "log-observation" "$sug_skill"
  assert_contains "require a missing" "$sug_skill"
}

# --- common.sh invariant ---

@test "DEFAULT_STATE carries the learnings key" {
  run grep DEFAULT_STATE "$REPO_ROOT/bin/lib/common.sh"
  assert_contains '"learnings":[]' "$output"
}
