#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO/claude"
DEST="${CLAUDE_HOME:-$HOME/.claude}"
BACKUP="$DEST/backups/harness-$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0

usage() {
  cat <<EOF
Usage: ./install.sh [--dry-run]

Symlinks agents, skills and CLAUDE.md from $SRC into $DEST.
Existing non-symlink targets are moved to $DEST/backups/harness-<timestamp>/.
Dangling symlinks into this repo are removed.
EOF
}

case "${1:-}" in
  --dry-run) DRY_RUN=1 ;;
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) usage; exit 1 ;;
esac

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  [dry-run] $*"
  else
    "$@"
  fi
}

linked=0; unchanged=0; backed_up=0; pruned=0

link() {
  local src="$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    unchanged=$((unchanged + 1))
    return
  fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    run mkdir -p "$BACKUP"
    run mv "$dst" "$BACKUP/"
    echo "  backup  $dst → $BACKUP/"
    backed_up=$((backed_up + 1))
  fi
  run ln -s "$src" "$dst"
  echo "  link    $dst"
  linked=$((linked + 1))
}

prune() {
  local dir="$1" entry target
  for entry in "$dir"/*; do
    [ -L "$entry" ] || continue
    target="$(readlink "$entry")"
    case "$target" in
      "$SRC"/*)
        if [ ! -e "$target" ]; then
          run rm "$entry"
          echo "  prune   $entry"
          pruned=$((pruned + 1))
        fi
        ;;
    esac
  done
}

echo "harness: $SRC → $DEST"
run mkdir -p "$DEST/agents" "$DEST/skills"

for f in "$SRC"/agents/*.md; do
  link "$f" "$DEST/agents/$(basename "$f")"
done

for d in "$SRC"/skills/*/; do
  d="${d%/}"
  link "$d" "$DEST/skills/$(basename "$d")"
done

link "$SRC/CLAUDE.md" "$DEST/CLAUDE.md"

prune "$DEST/agents"
prune "$DEST/skills"

echo "done: linked=$linked unchanged=$unchanged backed_up=$backed_up pruned=$pruned"
