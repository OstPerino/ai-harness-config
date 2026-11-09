#!/bin/sh

input=$(cat)
untracked() {
  git -C "$1" ls-files --error-unmatch "$2" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 1 ] || [ "$rc" -eq 128 ]
}
command -v jq >/dev/null 2>&1 || exit 0
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[ -n "$file" ] && [ -f "$file" ] || exit 0

case "$file" in
  *.ts|*.tsx|*.mts|*.cts|*.vue|*/tsconfig.json) kind=ts; marker=tsconfig.json ;;
  *.rs|*/Cargo.toml) kind=rust; marker=Cargo.toml ;;
  *) exit 0 ;;
esac

dir=$(dirname "$file")
while :; do
  [ -f "$dir/$marker" ] && break
  if [ -e "$dir/.git" ] || [ "$dir" = "/" ] || [ "$dir" = "." ]; then
    exit 0
  fi
  dir=$(dirname "$dir")
done

if [ "$kind" = ts ]; then
  tool=tsc
  pkg=""
  d="$dir"
  while :; do
    if [ -f "$d/package.json" ]; then
      pkg="$d/package.json"
      break
    fi
    if [ -e "$d/.git" ] || [ "$d" = "/" ] || [ "$d" = "." ]; then
      break
    fi
    d=$(dirname "$d")
  done
  if [ -n "$pkg" ] && jq -e '[.dependencies, .devDependencies, .peerDependencies] | map(select(type == "object") | has("vue") or has("vue-tsc")) | any' "$pkg" >/dev/null 2>&1; then
    tool=vue-tsc
  fi
  bin=""
  d="$dir"
  while :; do
    if [ -x "$d/node_modules/.bin/$tool" ] && untracked "$d" "node_modules/.bin/$tool"; then
      bin="$d/node_modules/.bin/$tool"
      break
    fi
    if [ -e "$d/.git" ] || [ "$d" = "/" ] || [ "$d" = "." ]; then
      break
    fi
    d=$(dirname "$d")
  done
  if [ -z "$bin" ]; then
    bin=$(command -v "$tool" 2>/dev/null) || exit 0
  fi
  if jq -e '(.references // []) | length > 0' "$dir/tsconfig.json" >/dev/null 2>&1; then
    if [ "$tool" = vue-tsc ]; then build=--build; else build=-b; fi
  else
    build=""
  fi
else
  tool=cargo
  bin=$(command -v cargo 2>/dev/null) || exit 0
fi

tmp=$(mktemp "${TMPDIR:-/tmp}/typecheck-out.XXXXXX") || exit 0
trap 'rm -f "$tmp"' EXIT
trap 'exit 1' INT TERM HUP

rc=0
if [ "$kind" = ts ]; then
  if [ -n "$build" ]; then
    (cd "$dir" && "$bin" "$build" --noEmit) >"$tmp" 2>&1 || rc=$?
  else
    (cd "$dir" && "$bin" --noEmit) >"$tmp" 2>&1 || rc=$?
  fi
else
  (cd "$dir" && "$bin" check) >"$tmp" 2>&1 || rc=$?
fi

seen="${TMPDIR:-/tmp}/typecheck.$(printf '%s' "$dir" | cksum | cut -d' ' -f1)"

if [ "$rc" -eq 0 ]; then
  rm -f "$seen"
  exit 0
fi

sum=$(cksum <"$tmp")
if [ -f "$seen" ] && [ "$(cat "$seen" 2>/dev/null)" = "$sum" ]; then
  exit 0
fi
printf '%s\n' "$sum" >"$seen" 2>/dev/null

printf 'typecheck: %s failed in %s (exit %s)\n' "$tool" "$dir" "$rc" >&2
cat "$tmp" >&2
exit 2
