# rules.sh: The standing rules every session loads (preload rules, and the
# Claude SessionStart context). Output is capped at RULES_BUDGET characters.

RULES_JQ='
def line_len: length + 1;
def body_text: gsub("\u001d"; "\n") | gsub("^\\s+|\\s+$"; "")
  | sub("^## Instruction[ \\t]*\\n"; "") | gsub("^\\s+|\\s+$"; "");
[rows | select(valid)] as $v
| ($v | map(select(.scope == "project") | {(.id): true}) | add // {}) as $pids
| ($v | map(select(.archived != "true"))) as $live
| ($live | map(select(.scope == "project" or ($pids[.id] | not))) | sort_by(.id)) as $act
| ($act | map(select(.kind == "rule") | . + {text: "### \(.id)\n\(.body | body_text)"})) as $rules
| ($act | map(select(.kind != "rule") | .id)) as $procs
| ($live | map(select(.kind == "")) | length) as $uncl
| "These are the user'"'"'s standing rules from habit. Follow them in this session." as $head
| "Procedures (load with read-habit <id> when relevant): " as $pre
| (if $uncl > 0 then "\($uncl) unclassified habit\(if $uncl == 1 then "" else "s" end): run /habit:distill maintain." else "" end) as $ul
| (($head | line_len) + (if $due != "" then $due | line_len else 0 end)
   + (if $ul != "" then $ul | line_len else 0 end)
   + ("INJECTED: " | line_len) + ("Rules not loaded (budget): " | line_len)
   + ($rules | map(.id | length + 2) | add // 0)
   + (if ($procs | length) > 0 then ($pre | length) + 13 else 0 end)) as $fixed
| ($rules | map(select(.scope == "project")) + map(select(.scope == "global"))
   | reduce .[] as $r ({used: 0, ids: {}};
       if .used + ($r.text | line_len) <= $budget - $fixed
       then .used += ($r.text | line_len) | .ids[$r.id] = true else . end)) as $pick
| ($rules | map(select($pick.ids[.id]))) as $in
| ($rules | map(select($pick.ids[.id] | not) | .id)) as $out
| ([$head] + ($in | map(select(.scope == "global") | .text)) + ($in | map(select(.scope == "project") | .text))
   + (if ($out | length) > 0 then ["Rules not loaded (budget): " + ($out | join(", "))] else [] end)) as $top
| ([(if $due != "" then $due else empty end), (if $ul != "" then $ul else empty end),
    "INJECTED: " + ($in | map(select(.scope == "global")) + map(select(.scope == "project")) | map(.id) | join(","))]) as $tail
| ($budget - ($top + $tail | map(line_len) | add) - 1 - ($pre | length)) as $room
| (reduce $procs[] as $p ({n: 0, len: 0};
    if .n == .k then . else
    (.len + ($p | length) + (if .n > 0 then 2 else 0 end)) as $l
    | (($procs | length) - .n - 1) as $rest
    | if $l + (if $rest > 0 then 12 else 0 end) <= $room then .n += 1 | .len = $l else .k = .n end end)) as $fit
| ($procs | length - $fit.n) as $rest
| (if ($procs | length) == 0 then []
   else [$pre + ($procs[0:$fit.n] | join(", "))
         + (if $rest > 0 then (if $fit.n > 0 then " " else "" end) + "(+\($rest) more)" else "" end)] end) as $pl
| if ($rules | length) + ($procs | length) == 0 and $due == "" and $ul == "" then empty
  else $top + $pl + $tail | join("\n") end
'

# rules_render <due line or empty>: print the rules context, or nothing when
# there are no habits to mention and distill is not due.
rules_render() {
  local pdir
  pdir=$(project_dir) || pdir=""
  jq -nr --rawfile rows <(_index_rows "$pdir") --arg due "${1:-}" \
    --argjson budget "$RULES_BUDGET" "$INDEX_JQ_DEFS$RULES_JQ"
}

# preload rules: the due line ignores the notice throttle.
rules_preload() {
  local due=""
  if due_check; then due=$(_nudge_text); fi
  rules_render "$due"
}
