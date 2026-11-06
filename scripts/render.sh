#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
mode=write
out=$ROOT
case ${1:-} in
  --check) mode=check; shift ;;
  --output) [ "$#" -eq 2 ] || exit 1; out=$2; shift 2 ;;
  '') ;;
  *) printf 'usage: render.sh [--check | --output DIRECTORY]\n' >&2; exit 1 ;;
esac
[ "$#" -eq 0 ] || exit 1
command -v jq >/dev/null 2>&1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/build"
render() {
  jq -jRs --slurpfile tokens "$tmp/tokens.json" '
    reduce ($tokens[0] | to_entries[]) as $t (.; split($t.key) | join($t.value))
    | if test("\\{\\{[A-Z_]+\\}\\}") then error("unresolved adapter token") else . end
  ' "$1" >"$2"
}
for client in claude codex; do
  case $client in
    claude) work_mode=$ROOT/adapters/claude/work-mode.md ;;
    codex) work_mode=$ROOT/shared/rules/work-mode.md ;;
  esac
  jq --rawfile mode "$work_mode" '. + {"{{WORK_MODE}}": ($mode | sub("\n$"; ""))}' \
    "$ROOT/adapters/$client/tokens.json" >"$tmp/tokens.json"
  mkdir -p "$tmp/build/$client/agents" "$tmp/build/$client/skills"
  if [ "$client" = claude ]; then dest=CLAUDE.md; else dest=AGENTS.md; fi
  render "$ROOT/shared/rules/global.md" "$tmp/build/$client/$dest"
  if [ "$client" = codex ]; then cat "$ROOT/adapters/codex/instructions.md" >>"$tmp/build/$client/$dest"; fi
  for src in "$ROOT"/shared/roles/*.md; do
    name=$(basename "$src" .md)
    render "$src" "$tmp/body"
    if [ "$client" = claude ]; then
      cat "$ROOT/adapters/claude/$name.frontmatter" "$tmp/body" >"$tmp/build/$client/agents/$name.md"
    else
      desc=$(jq -r --arg name "$name" '.[] | select(.name == $name) | .description' "$ROOT/shared/roles/index.json")
      printf '%s' "$desc" >"$tmp/description"
      render "$tmp/description" "$tmp/description.rendered"
      jq -nr --arg name "$name" --rawfile desc "$tmp/description.rendered" --rawfile body "$tmp/body" '
        "name = " + ($name | tojson) + "\ndescription = " + ($desc | tojson) + "\ndeveloper_instructions = " + ($body | tojson)
      ' >"$tmp/build/$client/agents/$name.toml"
    fi
  done
  find "$ROOT/shared/skills" -type f | LC_ALL=C sort >"$tmp/sources"
  while IFS= read -r src; do
    rel=${src#"$ROOT/shared/skills/"}
    dest=$tmp/build/$client/skills/$rel
    mkdir -p "$(dirname "$dest")"
    case $src in
      *.md) render "$src" "$dest" ;;
      *) cp -p "$src" "$dest" ;;
    esac
    if [ "$client" = codex ] && [ "$(basename "$dest")" = SKILL.md ]; then
      awk 'NR==1 {fm=1; print; next} fm && /^---$/ {fm=0} fm && /^(disable-model-invocation|argument-hint):/ {next} {print}' "$dest" >"$tmp/skill"
      cp "$tmp/skill" "$dest"
      cat "$ROOT/adapters/codex/instructions.md" >>"$dest"
    fi
  done <"$tmp/sources"
done
mkdir -p "$tmp/build/claude/hooks" "$tmp/build/codex/legacy"
for src in "$ROOT"/shared/security/*.sh; do
  cp -p "$src" "$tmp/build/claude/hooks/"
  cp -p "$src" "$tmp/build/codex/legacy/"
done
rm -f "$tmp/build/codex/skills/harness-stats/stats.sh"
if [ -d "$ROOT/adapters/codex/skills" ]; then cp -R "$ROOT/adapters/codex/skills/." "$tmp/build/codex/skills/"; fi
if [ -d "$ROOT/adapters/codex/hooks" ]; then cp -R "$ROOT/adapters/codex/hooks" "$tmp/build/codex/"; fi
for name in learn harness-stats Telegram; do
  mkdir -p "$tmp/build/codex/skills/$name/agents"
  printf 'policy:\n  allow_implicit_invocation: false\n' >"$tmp/build/codex/skills/$name/agents/openai.yaml"
done
find "$tmp/build" -type f | sed "s|^$tmp/build/||" | LC_ALL=C sort >"$tmp/list"
errors=0
while IFS= read -r rel; do
  if ! cmp -s "$tmp/build/$rel" "$out/$rel"; then
    if [ "$mode" = check ]; then
      printf 'render: differs %s\n' "$rel" >&2
      errors=$((errors + 1))
    else
      mkdir -p "$(dirname "$out/$rel")"
      cp -p "$tmp/build/$rel" "$out/$rel"
    fi
  fi
done <"$tmp/list"
if [ "$mode" = write ]; then cp "$tmp/list" "$out/.generated-files"; else
  cmp -s "$tmp/list" "$out/.generated-files" || { printf 'render: generated file list differs\n' >&2; errors=$((errors + 1)); }
fi
[ "$errors" -eq 0 ] || exit 1
printf 'render: %s ok\n' "$mode"
