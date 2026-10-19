#!/bin/sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATS="${STATS_SH:-$ROOT/claude/skills/harness-stats/stats.sh}"
SH_BIN="${SH:-sh}"
pass=0
total=0

user_text() { printf '{"type":"user","timestamp":"%s","entrypoint":"%s","message":{"role":"user","content":"%s"}}\n' "$1" "$2" "$3"; }
assistant_tools() {
  printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","usage":{"output_tokens":%s,"input_tokens":1},"content":[%s]}}\n' "$1" "$2" "$3"
}
tool_error() { printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":[{"type":"tool_result","is_error":true,"content":"%s"}]}}\n' "$1" "$2"; }
tool_ok() { printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":[{"type":"tool_result","content":"%s"}]}}\n' "$1" "$2"; }
hook_failure() { printf '{"type":"attachment","timestamp":"%s","attachment":{"type":"hook_non_blocking_error"}}\n' "$1"; }

build() {
  p="$sb/home/projects/-proj-a"
  mkdir -p "$p/s-after/subagents" "$p/s-before" || return 1
  {
    user_text 2026-01-01T10:00:00Z cli "fix the build"
    assistant_tools 2026-01-01T10:00:01Z 100 '{"type":"tool_use","name":"Bash","input":{}}'
    hook_failure 2026-01-01T10:00:02Z
    user_text 2026-01-01T10:01:00Z cli "опять не так"
    user_text 2026-01-01T10:02:00Z cli "[Request interrupted by user]"
  } >"$p/s-before.jsonl"
  {
    user_text 2026-02-01T10:00:00Z cli "add a feature"
    assistant_tools 2026-02-01T10:00:01Z 50 '{"type":"tool_use","name":"Agent","input":{"subagent_type":"planner"}},{"type":"tool_use","name":"Bash","input":{}}'
    tool_error 2026-02-01T10:00:02Z "guard-net: file contents to network"
    tool_ok 2026-02-01T10:00:03Z "typecheck: tsc failed in /p (exit 2)"
    user_text 2026-02-01T10:01:00Z cli "<task-notification>done</task-notification>"
  } >"$p/s-after.jsonl"
  {
    assistant_tools 2026-02-01T10:00:05Z 30 '{"type":"tool_use","name":"Read","input":{}}'
    tool_error 2026-02-01T10:00:06Z "No such file"
  } >"$p/s-after/subagents/agent-x.jsonl"
  {
    user_text 2026-02-02T10:00:00Z sdk-cli "headless eval"
    assistant_tools 2026-02-02T10:00:01Z 999 '{"type":"tool_use","name":"Bash","input":{}}'
  } >"$p/s-headless.jsonl"
}

run_case() {
  name=$1
  shift
  total=$((total + 1))
  (
    sb=$(mktemp -d "${TMPDIR:-/tmp}/stats-test.XXXXXX") || exit 1
    [ -n "$sb" ] && [ -d "$sb" ] || exit 1
    trap 'rm -rf "$sb"' EXIT
    build || exit 1
    "$@"
  )
  rc=$?
  if [ "$rc" -eq 0 ]; then
    pass=$((pass + 1))
    echo "ok $name"
  else
    echo "FAIL $name"
  fi
}

report() { CLAUDE_HOME="$sb/home" "$SH_BIN" "$STATS" --split 2026-01-15 --json "$@"; }

expect() {
  got=$(report $2 | jq -r "$1") || { echo "  jq failed for $1" >&2; return 1; }
  [ "$got" = "$3" ] || { echo "  $1: expected $3, got $got" >&2; return 1; }
}

c_split_sessions() { expect '[.before.sessions, .after.sessions] | join(",")' "" "1,1"; }
c_prompts_skip_notifications() { expect '[.before.prompts, .after.prompts] | join(",")' "" "2,1"; }
c_interrupt_counted() { expect '.before.interrupts' "" "1"; }
c_frustration_counted() { expect '.before.frustration' "" "1"; }
c_hook_failure_counted() { expect '.before.hook_failures' "" "1"; }
c_guard_block_counted() { expect '.after.hook_blocks' "" "1"; }
c_typecheck_counted() { expect '.after.typecheck' "" "1"; }
c_subagent_tools_added() { expect '[.after.tools, .after.errors] | join(",")' "" "3,2"; }
c_agent_types() { expect '.after.agents.planner' "" "1"; }
c_headless_skipped() { expect '.after.out_tokens' "" "80"; }
c_headless_with_all() { expect '.after.sessions' "--all" "2"; }
c_since_filter() { expect '.before.sessions' "--since 2026-01-10" "0"; }
c_save_writes_snapshot() {
  report --save >/dev/null 2>&1 || return 1
  ls "$sb/home/harness-stats/"*.json >/dev/null 2>&1
}
c_table_output() {
  out=$(CLAUDE_HOME="$sb/home" "$SH_BIN" "$STATS" --split 2026-01-15) || return 1
  printf '%s' "$out" | grep -q '^interrupts per 100 prompts *50 *0$'
}
c_no_split_no_manifest_fails() {
  CLAUDE_HOME="$sb/home" "$SH_BIN" "$STATS" >/dev/null 2>&1 && return 1
  return 0
}
c_bad_arg_fails() {
  CLAUDE_HOME="$sb/home" "$SH_BIN" "$STATS" --nope >/dev/null 2>&1 && return 1
  return 0
}

for c in split_sessions prompts_skip_notifications interrupt_counted frustration_counted \
  hook_failure_counted guard_block_counted typecheck_counted subagent_tools_added agent_types \
  headless_skipped headless_with_all since_filter save_writes_snapshot table_output \
  no_split_no_manifest_fails bad_arg_fails; do
  run_case "$c" "c_$c"
done

echo "$pass/$total passed"
[ "$pass" -eq "$total" ]
