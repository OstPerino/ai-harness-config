#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN="${SH:-sh}"

passed=0
total=0

record() {
  total=$((total + 1))
  if [ "$2" -eq 0 ]; then
    passed=$((passed + 1))
    printf 'gate: ok %s\n' "$1"
  else
    printf 'gate: FAIL %s (exit %s)\n' "$1" "$2"
  fi
}

set +e
# shellcheck disable=SC2086
$RUN "$ROOT/tests/lint-harness.sh"
rc=$?
set -e
record tests/lint-harness.sh "$rc"

set +e
bash -n "$ROOT/install.sh"
rc=$?
set -e
record "bash -n install.sh" "$rc"

found=0
for f in "$ROOT"/tests/*.test.sh; do
  if [ "$f" = "$ROOT/tests/*.test.sh" ] && [ ! -e "$f" ]; then
    break
  fi
  found=1
  set +e
  # shellcheck disable=SC2086
  $RUN "$f"
  rc=$?
  set -e
  record "tests/$(basename "$f")" "$rc"
done

if [ "$found" -eq 0 ]; then
  total=$((total + 1))
  printf 'gate: FAIL no tests/*.test.sh found\n'
fi

set +e
home_hits=$(git -C "$ROOT" grep -n -E '[/]Users/[^/<.]+/' -- . ':!issues' 2>&1)
rc=$?
set -e
if [ "$rc" -eq 1 ]; then
  record "no home paths in tracked files" 0
else
  [ "$rc" -ne 0 ] || printf '%s\n' "$home_hits"
  record "no home paths in tracked files" 1
fi

printf 'gate: %s/%s passed\n' "$passed" "$total"
[ "$passed" -eq "$total" ] || exit 1
