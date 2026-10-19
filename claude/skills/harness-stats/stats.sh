#!/bin/sh
set -eu

usage() {
  cat <<EOF
Usage: stats.sh [--split YYYY-MM-DD] [--since YYYY-MM-DD] [--project SUBSTR] [--all] [--json] [--save]

Reads Claude Code transcripts from \${CLAUDE_HOME:-~/.claude}/projects and compares
sessions started before and after --split (default: date of the harness manifest).
Headless runs (claude -p, entrypoint sdk-cli) are skipped unless --all.
--save also writes the JSON report to $home/harness-stats/<today>.json.
EOF
}

home="${CLAUDE_HOME:-$HOME/.claude}"
split=""
since=""
project=""
json=0
all=0
save=0
while [ $# -gt 0 ]; do
  case "$1" in
    --split) split="${2:?}"; shift 2 ;;
    --since) since="${2:?}"; shift 2 ;;
    --project) project="${2:?}"; shift 2 ;;
    --json) json=1; shift ;;
    --all) all=1; shift ;;
    --save) save=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "stats: jq not found" >&2; exit 1; }
[ -d "$home/projects" ] || { echo "stats: no transcripts in $home/projects" >&2; exit 1; }

if [ -z "$split" ] && [ -f "$home/.ai-harness-managed.json" ]; then
  split=$(date -r "$home/.ai-harness-managed.json" +%Y-%m-%d 2>/dev/null || stat -c %y "$home/.ai-harness-managed.json" | cut -c1-10)
fi
[ -n "$split" ] || { echo "stats: no --split and no harness manifest" >&2; exit 1; }

session_prog='
def texts: if (.message.content | type) == "string" then [.message.content]
  else [.message.content[]? | select(.type == "text") | .text] end;
def human: .type == "user" and (.isSidechain | not) and (.isMeta | not)
  and ((.message.content | type) == "string" or ([.message.content[]? | select(.type == "tool_result")] | length) == 0);
def results: [.message.content[]? | select(.type == "tool_result")];
def rtext: .content | if type == "string" then . else ([.[]? | .text? // empty] | join(" ")) end;
reduce inputs as $r ({start: null, entry: null, prompts: 0, interrupts: 0, frustration: 0, tools: 0, errors: 0, hook_blocks: 0, hook_failures: 0, typecheck: 0, agents: {}, out_tokens: 0, in_tokens: 0};
  (if .start == null and ($r.timestamp // null) != null then .start = $r.timestamp else . end)
  | (if .entry == null and ($r.entrypoint // null) != null then .entry = $r.entrypoint else . end)
  | if $r.type == "assistant" then
      ([$r.message.content[]? | select(.type == "tool_use")]) as $tu
      | .tools += ($tu | length)
      | .agents = reduce ($tu[] | select(.name == "Agent" or .name == "Task") | (.input.subagent_type // "general-purpose")) as $a (.agents; .[$a] += 1)
      | .out_tokens += ($r.message.usage.output_tokens // 0)
      | .in_tokens += (($r.message.usage.input_tokens // 0) + ($r.message.usage.cache_creation_input_tokens // 0) + ($r.message.usage.cache_read_input_tokens // 0))
    elif $r.type == "user" then
      ($r | results) as $res
      | .errors += ([$res[] | select(.is_error == true)] | length)
      | .hook_blocks += ([$res[] | select(.is_error == true) | rtext | select(test("^(guard-[a-z]+|jira-write-guard|typecheck): |hook (blocking|denied)"; "m"))] | length)
      | .typecheck += ([$res[] | rtext | select(test("^typecheck: "; "m"))] | length)
      | (($r | texts | join(" ")) as $t
         | if ($t | test("\\[Request interrupted by user")) then .interrupts += 1
           elif ($r | human) and ($t | length) > 0 and ($t | test("^\\s*<") | not) then
             .prompts += 1
             | if ($t | test("бля|пизд|нахуй|хуйн|опять|не так|не то |косяк|сломал|почему ты|зачем ты|wtf|why did you|you broke"; "i")) then .frustration += 1 else . end
           else . end)
    elif $r.type == "attachment" then
      (($r.attachment.type // "") | tostring) as $at
      | if $at == "hook_non_blocking_error" then .hook_failures += 1 else . end
    else . end)
'

sub_prog='
def results: [.message.content[]? | select(.type == "tool_result")];
def rtext: .content | if type == "string" then . else ([.[]? | .text? // empty] | join(" ")) end;
reduce inputs as $r ({tools: 0, errors: 0, hook_blocks: 0, typecheck: 0, out_tokens: 0};
  if $r.type == "assistant" then
    .tools += ([$r.message.content[]? | select(.type == "tool_use")] | length)
    | .out_tokens += ($r.message.usage.output_tokens // 0)
  elif $r.type == "user" then
    ($r | results) as $res
    | .errors += ([$res[] | select(.is_error == true)] | length)
    | .hook_blocks += ([$res[] | select(.is_error == true) | rtext | select(test("^(guard-[a-z]+|jira-write-guard|typecheck): |hook (blocking|denied)"; "m"))] | length)
    | .typecheck += ([$res[] | rtext | select(test("^typecheck: "; "m"))] | length)
  else . end)
'

tmp=$(mktemp "${TMPDIR:-/tmp}/harness-stats.XXXXXX")
trap 'rm -f "$tmp"' EXIT INT TERM HUP

for dir in "$home"/projects/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  if [ -n "$project" ]; then
    case "$name" in *"$project"*) ;; *) continue ;; esac
  fi
  for f in "$dir"*.jsonl; do
    [ -f "$f" ] || continue
    id=$(basename "$f" .jsonl)
    s=$(jq -c -n "$session_prog" <"$f" 2>/dev/null) || continue
    subs='{"tools":0,"errors":0,"hook_blocks":0,"typecheck":0,"out_tokens":0}'
    if [ -d "$dir$id/subagents" ]; then
      for a in "$dir$id"/subagents/agent-*.jsonl; do
        [ -f "$a" ] || continue
        one=$(jq -c -n "$sub_prog" <"$a" 2>/dev/null) || continue
        subs=$(jq -c -n --argjson x "$subs" --argjson y "$one" '$x | with_entries(.value += $y[.key])')
      done
    fi
    jq -c -n --argjson s "$s" --argjson sub "$subs" --arg project "$name" \
      '$s + {project: $project, sub: $sub}' >>"$tmp"
  done
done

report=$(jq -s -c --arg split "$split" --arg since "$since" --argjson all "$all" '
  map(select(.start != null and .prompts > 0 and (($since == "") or (.start[0:10] >= $since)) and ($all == 1 or .entry != "sdk-cli")))
  | def agg: {
      sessions: length,
      prompts: (map(.prompts) | add // 0),
      interrupts: (map(.interrupts) | add // 0),
      frustration: (map(.frustration) | add // 0),
      tools: (map(.tools + .sub.tools) | add // 0),
      errors: (map(.errors + .sub.errors) | add // 0),
      hook_blocks: (map(.hook_blocks + .sub.hook_blocks) | add // 0),
      hook_failures: (map(.hook_failures) | add // 0),
      typecheck: (map(.typecheck + .sub.typecheck) | add // 0),
      subagents: (map(.agents | add // 0) | add // 0),
      out_tokens: (map(.out_tokens + .sub.out_tokens) | add // 0),
      agents: (map(.agents | to_entries[]) | group_by(.key) | map({key: .[0].key, value: (map(.value) | add)}) | from_entries)
    };
  {split: $split, before: (map(select(.start[0:10] < $split)) | agg), after: (map(select(.start[0:10] >= $split)) | agg)}
' "$tmp")

if [ "$save" -eq 1 ]; then
  mkdir -p "$home/harness-stats"
  out="$home/harness-stats/$(date +%Y-%m-%d).json"
  printf '%s\n' "$report" >"$out"
  echo "saved: $out" >&2
fi

if [ "$json" -eq 1 ]; then
  printf '%s\n' "$report"
  exit 0
fi

printf '%s' "$report" | jq -r '
  def r($a; $b): if $b == 0 then "—" else (($a * 10 / $b | round) / 10 | tostring) end;
  def p($a; $b): if $b == 0 then "—" else (($a * 1000 / $b | round) / 10 | tostring) + "%" end;
  def row($label; f): "\($label)\t\(.before | f)\t\(.after | f)";
  "harness-stats: split \(.split) (before < split <= after)",
  "metric\tbefore\tafter",
  row("sessions"; .sessions | tostring),
  row("prompts per session"; r(.prompts; .sessions)),
  row("interrupts per 100 prompts"; r(.interrupts * 100; .prompts)),
  row("frustration per 100 prompts"; r(.frustration * 100; .prompts)),
  row("tool calls per prompt"; r(.tools; .prompts)),
  row("tool error rate"; p(.errors; .tools)),
  row("hook blocks per session"; r(.hook_blocks; .sessions)),
  row("broken hook runs per session"; r(.hook_failures; .sessions)),
  row("typecheck reports per session"; r(.typecheck; .sessions)),
  row("subagents per session"; r(.subagents; .sessions)),
  row("output tokens per prompt"; r(.out_tokens; .prompts)),
  "",
  "subagents after split: \(.after.agents | to_entries | sort_by(-.value) | map("\(.key)=\(.value)") | join(", "))"
' | awk -F '\t' '{ if (NF == 3) printf "%-32s %10s %10s\n", $1, $2, $3; else print }'
