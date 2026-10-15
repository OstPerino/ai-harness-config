#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE="$ROOT/claude"
errors=0

err() {
  printf 'lint: %s: %s\n' "$1" "$2" >&2
  errors=$((errors + 1))
}

frontmatter() {
  awk 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} NR>1 {print}' "$1"
}

field() {
  frontmatter "$1" | awk -v key="$2" '
    found && /^[[:space:]]+[^[:space:]]/ { sub(/^[[:space:]]+/, ""); printf "%s ", $0; next }
    found { exit }
    index($0, key ":") == 1 {
      value = substr($0, length(key) + 2)
      sub(/^[[:space:]]+/, "", value)
      if (value ~ /^[>|][-+]?$/) { found = 1; next }
      print value
      exit
    }'
}

for skill in "$CLAUDE"/skills/*/; do
  dir=$(basename "$skill")
  file="$skill/SKILL.md"
  if [ ! -f "$file" ]; then
    err "skills/$dir" "missing SKILL.md"
    continue
  fi
  name=$(field "$file" name)
  [ "$name" = "$dir" ] || err "skills/$dir/SKILL.md" "name '$name' does not match directory"
  [ -n "$(field "$file" description)" ] || err "skills/$dir/SKILL.md" "missing description"
done

for agent in "$CLAUDE"/agents/*.md; do
  base=$(basename "$agent" .md)
  name=$(field "$agent" name)
  [ "$name" = "$base" ] || err "agents/$base.md" "name '$name' does not match file name"
  [ -n "$(field "$agent" description)" ] || err "agents/$base.md" "missing description"
  model=$(field "$agent" model)
  case "$model" in
    "" | opus | sonnet | haiku | fable | inherit) ;;
    *) err "agents/$base.md" "model '$model' is not an alias (opus|sonnet|haiku|fable|inherit); harness policy pins aliases so agents follow new model versions" ;;
  esac
done

refs=$(grep -rln --exclude=VENDORED.md 'superpowers:' "$CLAUDE" 2>/dev/null || true)
for f in $refs; do
  err "${f#"$ROOT"/}" "references superpowers: skill namespace"
done

for skill in spec sdd; do
  [ -d "$CLAUDE/skills/$skill" ] || continue
  if grep -rqn 'general-purpose' "$CLAUDE/skills/$skill"; then
    err "skills/$skill" "dispatches general-purpose instead of harness agents"
  fi
done

[ "$errors" -eq 0 ] || { printf 'lint: %s problem(s)\n' "$errors" >&2; exit 1; }
echo "lint: ok"
