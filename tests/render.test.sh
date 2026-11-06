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
printf '\n{{UNKNOWN_TOKEN}}\n' >>"$TMP/copy with spaces/shared/rules/global.md"
if sh "$TMP/copy with spaces/scripts/render.sh" >"$TMP/log" 2>&1; then echo 'unknown token accepted' >&2; exit 1; fi
echo 'render: parity, determinism, drift, unknown token, paths with spaces: ok'
