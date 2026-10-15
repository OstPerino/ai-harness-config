#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_SH="${INSTALL_SH:-$ROOT/install.sh}"

if [ ! -f "$INSTALL_SH" ] || [ ! -r "$INSTALL_SH" ]; then
  printf 'install-test: cannot read INSTALL_SH: %s\n' "$INSTALL_SH" >&2
  exit 2
fi

SCENARIO=""
sb=""
status=0

sandbox() {
  sb=$(mktemp -d "${TMPDIR:-/tmp}/install-test.XXXXXX")
  sb=$(cd "$sb" && pwd)
  trap 'rm -rf "${sb:?}"' EXIT
  mkdir -p "$sb/repo/claude/agents" "$sb/repo/claude/skills/s1" "$sb/repo/claude/skills/s2" "$sb/home"
  cp "$INSTALL_SH" "$sb/repo/install.sh"
  printf 'a\n' >"$sb/repo/claude/agents/a.md"
  printf 'b\n' >"$sb/repo/claude/agents/b.md"
  printf 's1\n' >"$sb/repo/claude/skills/s1/SKILL.md"
  printf 's2\n' >"$sb/repo/claude/skills/s2/SKILL.md"
  printf 'claude\n' >"$sb/repo/claude/CLAUDE.md"
}

run_install() {
  status=0
  CLAUDE_HOME="$sb/home" HOME="$sb" bash "$sb/repo/install.sh" "$@" >"$sb/out" 2>&1 || status=$?
}

fail() {
  printf 'FAIL %s: %s / %s\n' "$SCENARIO" "$1" "$2"
  exit 1
}

assert_status() {
  [ "$status" -eq "$1" ] || fail "exit status $1" "exit status $status"
}

assert_link() {
  [ -L "$1" ] || fail "symlink $1" "not a symlink"
  actual=$(readlink "$1")
  [ "$actual" = "$2" ] || fail "$1 -> $2" "$1 -> $actual"
}

assert_not_exists() {
  if [ -e "$1" ] || [ -L "$1" ]; then
    fail "$1 absent" "$1 exists"
  fi
}

assert_output_contains() {
  grep -F -- "$1" "$sb/out" >/dev/null 2>&1 ||
    fail "output contains '$1'" "$(tail -n 5 "$sb/out" | tr '\n' '|')"
}

snapshot() {
  ls -lAR "$1" >"$2"
}

assert_tree_unchanged() {
  snapshot "$1" "$sb/snapshot.after"
  cmp -s "$2" "$sb/snapshot.after" || fail "$1 unchanged" "$(diff "$2" "$sb/snapshot.after" | tr '\n' '|')"
}

t_link() {
  run_install
  assert_status 0
  assert_link "$sb/home/agents/a.md" "$sb/repo/claude/agents/a.md"
  assert_link "$sb/home/agents/b.md" "$sb/repo/claude/agents/b.md"
  assert_link "$sb/home/skills/s1" "$sb/repo/claude/skills/s1"
  assert_link "$sb/home/skills/s2" "$sb/repo/claude/skills/s2"
  assert_link "$sb/home/CLAUDE.md" "$sb/repo/claude/CLAUDE.md"
  assert_output_contains "linked=5 unchanged=0 backed_up=0 pruned=0"
}

t_unchanged() {
  mkdir -p "$sb/home/agents" "$sb/home/skills"
  ln -s "$sb/repo/claude/agents/a.md" "$sb/home/agents/a.md"
  ln -s "$sb/repo/claude/agents/b.md" "$sb/home/agents/b.md"
  ln -s "$sb/repo/claude/skills/s1" "$sb/home/skills/s1"
  ln -s "$sb/repo/claude/skills/s2" "$sb/home/skills/s2"
  ln -s "$sb/repo/claude/CLAUDE.md" "$sb/home/CLAUDE.md"
  snapshot "$sb/home" "$sb/snapshot.before"
  run_install
  assert_status 0
  assert_output_contains "linked=0 unchanged=5 backed_up=0 pruned=0"
  assert_tree_unchanged "$sb/home" "$sb/snapshot.before"
  assert_not_exists "$sb/home/backups"
}

t_dry_run() {
  snapshot "$sb/home" "$sb/snapshot.before"
  run_install --dry-run
  assert_status 0
  assert_tree_unchanged "$sb/home" "$sb/snapshot.before"
  assert_output_contains "[dry-run]"
}

t_bad_arg() {
  run_install --nope
  assert_status 1
  assert_output_contains "Usage:"
  assert_not_exists "$sb/home/agents"
}

passed=0
total=0
for SCENARIO in link unchanged dry-run bad-arg; do
  total=$((total + 1))
  fn="t_$(printf '%s' "$SCENARIO" | tr - _)"
  if ( sandbox; "$fn" ); then
    passed=$((passed + 1))
    printf 'ok %s\n' "$SCENARIO"
  fi
done

printf '%s/%s passed\n' "$passed" "$total"
[ "$passed" -eq "$total" ] || exit 1
