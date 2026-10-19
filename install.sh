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

Symlinks agents, skills, hooks and CLAUDE.md from $SRC into $DEST.
Merges $SRC/settings.d/*.json into $DEST/settings.json; what it adds is recorded
in $DEST/.ai-harness-managed.json and removed again on the next run. Needs jq.
Existing non-symlink targets are moved to $DEST/backups/harness-<timestamp>/.
Dangling symlinks into this repo are removed.
EOF
}

die() {
  echo "install: $*" >&2
  exit 1
}

if [ -z "${CLAUDE_HOME:-}" ] && command -v git >/dev/null 2>&1; then
  git_dir="$(cd "$REPO" && cd "$(git rev-parse --git-dir 2>/dev/null)" 2>/dev/null && pwd -P)" || git_dir=""
  common_dir="$(cd "$REPO" && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)" || common_dir=""
  if [ -n "$git_dir" ] && [ -n "$common_dir" ] && [ "$git_dir" != "$common_dir" ]; then
    die "run install.sh from the main checkout, not from a linked worktree ($REPO)"
  fi
fi

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

MANIFEST="$DEST/.ai-harness-managed.json"
SETTINGS="$DEST/settings.json"
FRAGS=()
TMPS=()
settings_state=skipped
settings_changed=0
manifest_changed=0
cur_json='{}'
new_json='{}'
new_manifest=null
interim_manifest=null
trap 'for t in ${TMPS[@]+"${TMPS[@]}"}; do rm -f "$t"; done' EXIT

read -r -d '' JQ_DEFS <<'JQ' || true
def gp($p): try getpath($p) catch null;
def mergeR($b):
  if type == "object" and ($b | type) == "object" then
    reduce ($b | keys_unsorted[]) as $k (.; .[$k] = (if has($k) then (.[$k] | mergeR($b[$k])) else $b[$k] end))
  elif type == "array" and ($b | type) == "array" then
    reduce $b[] as $e (.; if any(.[]; . == $e) then . else . + [$e] end)
  else $b end;
def unapply($m):
  reduce ($m.elements // [])[] as $e (.;
    if (gp($e.path) | type) == "array" then setpath($e.path; gp($e.path) | (index([$e.value]) as $i | if $i == null then . else del(.[$i]) end)) else . end)
  | reduce ($m.scalars // [])[] as $x (.;
    if gp($x.path) == $x.value then (if $x.had then setpath($x.path; $x.prev) else delpaths([$x.path]) end) else . end)
  | reduce (($m.created // []) | sort_by(length) | reverse)[] as $p (.;
    if (gp($p) as $c | $c == [] or $c == {}) then delpaths([$p]) else . end);
def own($path; $empty; $old):
  (.s | gp($path)) as $c
  | if ($path | length) == 0 then .
    elif $c == null then .s |= setpath($path; $empty) | .created += [$path]
    elif (($old.created // []) | any(. == $path)) then .created += [$path]
    else . end;
def ap($path; $r; $old):
  (.s | gp($path)) as $c
  | if ($r | type) == "object" and ($c == null or ($c | type) == "object") then
      own($path; {}; $old)
      | reduce ($r | keys_unsorted[]) as $k (.; ap($path + [$k]; $r[$k]; $old))
    elif ($r | type) == "array" and ($c == null or ($c | type) == "array") then
      own($path; []; $old)
      | reduce $r[] as $e (.;
          if (.s | gp($path) | any(.[]; . == $e)) then .
          else .s |= setpath($path; gp($path) + [$e]) | .elements += [{path: $path, value: $e}] end)
    else
      (($old.scalars // []) | map(select(.path == $path)) | .[0]) as $o
      | if $o == null and $c == $r then .
        else
          (if $o != null then {had: $o.had, prev: $o.prev} else {had: ($c != null), prev: $c} end) as $pv
          | .s |= setpath($path; $r)
          | .scalars += [{path: $path, value: $r} + $pv]
        end
    end;
JQ

read -r -d '' JQ_MAIN <<'JQ' || true
($s | unapply($m)) as $u
| {s: $u, scalars: [], elements: [], created: []}
| ap([]; $r; $m)
| {settings: .s, manifest: (if (.scalars + .elements + .created | length) == 0 then null else {version: 1, scalars, elements, created} end)}
JQ

settings_prepare() {
  local f man repo result old_m
  local LC_ALL=C
  for f in "$SRC"/settings.d/*.json; do
    if [ -e "$f" ]; then FRAGS+=("$f"); fi
  done
  if [ "${#FRAGS[@]}" -eq 0 ] && [ ! -e "$MANIFEST" ]; then return; fi
  command -v jq >/dev/null 2>&1 || die "jq is required to merge settings.d but was not found in PATH"
  for f in ${FRAGS[@]+"${FRAGS[@]}"} "$SETTINGS" "$MANIFEST"; do
    [ -e "$f" ] || continue
    jq -e -s 'length == 1 and (.[0] | type) == "object"' "$f" >/dev/null 2>&1 || die "not a valid JSON object: $f"
  done
  if [ -e "$MANIFEST" ]; then
    jq -e '.version == 1 and (.scalars | type) == "array" and (.elements | type) == "array" and (.created | type) == "array"' "$MANIFEST" >/dev/null 2>&1 || die "manifest has an unsupported schema (need version 1 with scalars, elements, created arrays): $MANIFEST"
  fi
  cur_json='{}'; man='{}'; repo='{}'; old_m=null
  if [ -e "$SETTINGS" ]; then cur_json="$(jq -c . "$SETTINGS")"; fi
  if [ -e "$MANIFEST" ]; then man="$(jq -c . "$MANIFEST")"; old_m="$man"; fi
  if [ "${#FRAGS[@]}" -gt 0 ]; then
    repo="$(jq -s -c "$JQ_DEFS"' reduce .[] as $f ({}; mergeR($f))' "${FRAGS[@]}")" || die "cannot merge fragments in $SRC/settings.d"
  fi
  result="$(jq -n -c --argjson s "$cur_json" --argjson m "$man" --argjson r "$repo" "$JQ_DEFS $JQ_MAIN")" || die "cannot merge settings.d into $SETTINGS"
  new_json="$(printf '%s' "$result" | jq -c .settings)"
  new_manifest="$(printf '%s' "$result" | jq -c .manifest)"
  settings_state=unchanged
  if [ "$new_json" != "$cur_json" ]; then settings_changed=1; settings_state=updated; fi
  if [ "$new_manifest" != "$old_m" ]; then manifest_changed=1; fi
  interim_manifest="$(jq -n -c --argjson o "$man" --argjson n "$new_manifest" '{version: 1, scalars: (($o.scalars // []) + ($n.scalars // [])), elements: (($o.elements // []) + ($n.elements // [])), created: (($o.created // []) + ($n.created // []))}')"
}

write_atomic() {
  local target="$1" content="$2" template="$3" tmp
  tmp="$(mktemp "$template")"
  TMPS+=("$tmp")
  if [ -f "$target" ]; then cp -p "$target" "$tmp"; fi
  printf '%s\n' "$content" >"$tmp"
  mv "$tmp" "$target"
}

settings_apply() {
  [ "$settings_state" != skipped ] || return 0
  if [ "$settings_changed" -eq 1 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      diff -u --label 'settings.json (current)' --label 'settings.json (after install)' \
        <(printf '%s' "$cur_json" | jq .) <(printf '%s' "$new_json" | jq .) || true
    else
      if [ "$manifest_changed" -eq 1 ] && [ "$new_manifest" != null ]; then
        write_atomic "$MANIFEST" "$(printf '%s' "$interim_manifest" | jq .)" "$DEST/.ai-harness-managed.json.XXXXXX"
      fi
      if [ -f "$SETTINGS" ]; then
        mkdir -p "$BACKUP"
        cp -p "$SETTINGS" "$BACKUP/settings.json"
        backed_up=$((backed_up + 1))
      fi
      write_atomic "$SETTINGS" "$(printf '%s' "$new_json" | jq .)" "$DEST/.settings.json.XXXXXX"
      echo "  merge   $SETTINGS"
    fi
  fi
  if [ "$manifest_changed" -eq 1 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "  [dry-run] update $MANIFEST"
    elif [ "$new_manifest" = null ]; then
      rm -f "$MANIFEST"
      echo "  remove  $MANIFEST"
    else
      write_atomic "$MANIFEST" "$(printf '%s' "$new_manifest" | jq .)" "$DEST/.ai-harness-managed.json.XXXXXX"
      echo "  manifest $MANIFEST"
    fi
  fi
}

settings_prepare

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

hook_files=()
for f in "$SRC"/hooks/*.sh; do
  if [ -e "$f" ]; then hook_files+=("$f"); fi
done
if [ "${#hook_files[@]}" -gt 0 ]; then
  run mkdir -p "$DEST/hooks"
  for f in "${hook_files[@]}"; do
    link "$f" "$DEST/hooks/$(basename "$f")"
  done
fi

prune "$DEST/agents"
prune "$DEST/skills"
prune "$DEST/hooks"

settings_apply

echo "done: linked=$linked unchanged=$unchanged backed_up=$backed_up pruned=$pruned settings=$settings_state"
