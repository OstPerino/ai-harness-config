#!/bin/sh
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty') || exit 1
[ -n "$tool" ] || exit 1
project=$(printf '%s' "$input" | jq -r '.tool_input.project_key // empty') || exit 1
case "$tool" in
  mcp__jira__jira_get_*|mcp__jira__jira_search*|mcp__jira__jira_download_*|mcp__jira__jira_batch_get_*)
    exit 0 ;;
  *delete*|*remove*)
    jq -n --arg t "$tool" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:("Удаление в Jira запрещено: "+$t)}}' ;;
  mcp__jira__jira_create_issue)
    same=$(printf '%s' "$input" | jq -r --arg e "${JIRA_AUTOCREATE_PROJECT:-}" '$e != "" and (.tool_input.project_key // "") == $e') || exit 1
    if [ "$same" = true ]; then
      jq -n --arg p "$JIRA_AUTOCREATE_PROJECT" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:("Создание задачи в "+$p+" разрешено без подтверждения")}}'
    else
      jq -n --arg p "$project" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:("Создание задачи в проекте "+$p)}}'
    fi ;;
  mcp__jira__*)
    jq -n --arg t "$tool" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:("Запись в Jira: "+$t)}}' ;;
esac
