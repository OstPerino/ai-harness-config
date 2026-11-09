#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/copy with spaces"
for item in shared adapters scripts .generated-files; do cp -R "$ROOT/$item" "$TMP/copy with spaces/"; done
sh "$TMP/copy with spaces/scripts/render.sh" --output "$TMP/first" >"$TMP/log" 2>&1
sh "$TMP/copy with spaces/scripts/render.sh" --output "$TMP/second" >"$TMP/log" 2>&1
diff -r "$TMP/first" "$TMP/second"
diff -r "$ROOT/claude/agents" "$TMP/first/claude/agents"
cmp "$ROOT/claude/CLAUDE.md" "$TMP/first/claude/CLAUDE.md"
for file in "$ROOT"/claude/hooks/*.sh; do cmp "$file" "$TMP/first/claude/hooks/$(basename "$file")"; done
cp -R "$TMP/first/." "$TMP/copy with spaces/"
printf '\nSynthetic shared rule.\n' >>"$TMP/copy with spaces/shared/rules/global.md"
if sh "$TMP/copy with spaces/scripts/render.sh" --check >"$TMP/log" 2>&1; then echo 'drift was not detected' >&2; exit 1; fi
sh "$TMP/copy with spaces/scripts/render.sh" >"$TMP/log" 2>&1
sh "$TMP/copy with spaces/scripts/render.sh" --check >"$TMP/log" 2>&1
rm "$TMP/copy with spaces/shared/roles/test-dev.md"
if sh "$TMP/copy with spaces/scripts/render.sh" --check >"$TMP/log" 2>&1; then echo 'deleted source was not detected' >&2; exit 1; fi
sh "$TMP/copy with spaces/scripts/render.sh" >"$TMP/log" 2>&1
test ! -e "$TMP/copy with spaces/codex/agents/test-dev.toml"
test ! -e "$TMP/copy with spaces/claude/agents/test-dev.md"
rm -r "$TMP/copy with spaces/shared/skills/domain-modeling"
sh "$TMP/copy with spaces/scripts/render.sh" >"$TMP/log" 2>&1
test ! -e "$TMP/copy with spaces/claude/skills/domain-modeling"
test ! -e "$TMP/copy with spaces/codex/skills/domain-modeling"
sh "$TMP/copy with spaces/scripts/render.sh" --check >"$TMP/log" 2>&1
printf 'claude/../../outside\n' >>"$TMP/copy with spaces/.generated-files"
if sh "$TMP/copy with spaces/scripts/render.sh" >"$TMP/log" 2>&1; then echo 'invalid generated path accepted' >&2; exit 1; fi
sed '$d' "$TMP/copy with spaces/.generated-files" >"$TMP/list"
cp "$TMP/list" "$TMP/copy with spaces/.generated-files"
mv "$TMP/copy with spaces/.generated-files" "$TMP/manifest"
touch "$TMP/foreign"
ln -s "$TMP/foreign" "$TMP/copy with spaces/.generated-files"
if sh "$TMP/copy with spaces/scripts/render.sh" >"$TMP/log" 2>&1; then echo 'symlinked generated manifest accepted' >&2; exit 1; fi
test ! -s "$TMP/foreign"
rm "$TMP/copy with spaces/.generated-files"
mv "$TMP/manifest" "$TMP/copy with spaces/.generated-files"
printf '\n{{UNKNOWN_TOKEN}}\n' >>"$TMP/copy with spaces/shared/rules/global.md"
if sh "$TMP/copy with spaces/scripts/render.sh" >"$TMP/log" 2>&1; then echo 'unknown token accepted' >&2; exit 1; fi
echo 'render: parity, determinism, drift, unknown token, paths with spaces: ok'
