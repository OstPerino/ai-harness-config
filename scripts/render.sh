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
  if [ -d "$ROOT/adapters/$client/skills" ]; then
    find "$ROOT/adapters/$client/skills" -type f | LC_ALL=C sort >"$tmp/overrides"
    while IFS= read -r src; do
      rel=${src#"$ROOT/adapters/$client/skills/"}
      dest=$tmp/build/$client/skills/$rel
      mkdir -p "$(dirname "$dest")"
      case $src in
        *.md) render "$src" "$dest" ;;
        *) cp -p "$src" "$dest" ;;
      esac
    done <"$tmp/overrides"
  fi
done
mkdir -p "$tmp/build/claude/hooks" "$tmp/build/codex/legacy"
for src in "$ROOT"/shared/security/*.sh; do
  cp -p "$src" "$tmp/build/claude/hooks/"
  cp -p "$src" "$tmp/build/codex/legacy/"
done
if [ -d "$ROOT/adapters/codex/hooks" ]; then cp -R "$ROOT/adapters/codex/hooks" "$tmp/build/codex/"; fi
for name in learn harness-stats Telegram; do
  mkdir -p "$tmp/build/codex/skills/$name/agents"
  printf 'policy:\n  allow_implicit_invocation: false\n' >"$tmp/build/codex/skills/$name/agents/openai.yaml"
done
find "$tmp/build" -type f | sed "s|^$tmp/build/||" | LC_ALL=C sort >"$tmp/list"
python3 - "$tmp" "$out" "$mode" <<'PY'
from pathlib import Path
import os, shutil, sys, tempfile
temp, out = map(Path, sys.argv[1:3])
out = out.resolve()
mode = sys.argv[3]
manifest = out / '.generated-files'
if manifest.is_symlink():
    raise SystemExit('render: symlinked generated file manifest')
current = (temp / 'list').read_text().splitlines()
previous = manifest.read_text().splitlines() if manifest.exists() else []
for rel in set(previous + current):
    path = Path(rel)
    if path.is_absolute() or '..' in path.parts or len(path.parts) < 2 or path.parts[0] not in ('claude', 'codex'):
        raise SystemExit('render: invalid generated path: ' + rel)
    dest = out / path
    if any(p.is_symlink() for p in (dest, *dest.parents) if p != out.parent):
        raise SystemExit('render: symlink in output path: ' + rel)
stale = sorted(set(previous) - set(current))
different = [rel for rel in current if not (out / rel).is_file() or (out / rel).read_bytes() != (temp / 'build' / rel).read_bytes()]
if mode == 'check':
    for rel in different + stale:
        print('render: differs ' + rel, file=sys.stderr)
    if different or stale or not manifest.exists() or manifest.read_bytes() != (temp / 'list').read_bytes():
        raise SystemExit('render: generated files need rebuilding')
else:
    for rel in stale:
        path = out / rel
        path.unlink(missing_ok=True)
        parent = path.parent
        while parent != out / Path(rel).parts[0]:
            try:
                parent.rmdir()
            except (FileNotFoundError, OSError):
                break
            parent = parent.parent
    for rel in different:
        dest = out / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(temp / 'build' / rel, dest)
    fd, pending = tempfile.mkstemp(prefix='.generated-', dir=out)
    os.close(fd)
    try:
        shutil.copy2(temp / 'list', pending)
        os.replace(pending, manifest)
    finally:
        Path(pending).unlink(missing_ok=True)
PY
printf 'render: %s ok\n' "$mode"
