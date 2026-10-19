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
  sb=$(mktemp -d "${TMPDIR:-/tmp}/install-test.XXXXXX") || exit 1
  [ -n "$sb" ] && [ -d "$sb" ] || exit 1
  sb=$(cd "$sb" && pwd) || exit 1
  case "${sb##*/}" in
    install-test.??????) ;;
    *) exit 1 ;;
  esac
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
  exit 70
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

assert_file_content() {
  [ -f "$1" ] && [ ! -L "$1" ] || fail "regular file $1" "missing or symlink"
  actual=$(cat "$1")
  [ "$actual" = "$2" ] || fail "$1 contains '$2'" "$1 contains '$actual'"
}

snapshot() {
  ls -liAR "$1" >"$2"
}

assert_tree_unchanged() {
  snapshot "$1" "$sb/snapshot.after"
  cmp -s "$2" "$sb/snapshot.after" || fail "$1 unchanged" "$(diff "$2" "$sb/snapshot.after" | tr '\n' '|')"
}

assert_json() {
  jq -e "$2" "$1" >/dev/null 2>&1 || fail "$1 satisfies jq '$2'" "$(jq -c . "$1" 2>&1 | head -c 400)"
}

frag() {
  mkdir -p "$sb/repo/claude/settings.d"
  printf '%s\n' "$2" >"$sb/repo/claude/settings.d/$1"
}

home_settings() {
  printf '%s\n' "$1" >"$sb/home/settings.json"
}

assert_one_backup_dir() {
  set -- "$sb"/home/backups/harness-*
  [ "$#" -eq 1 ] && [ -d "$1" ] || fail "exactly one directory home/backups/harness-*" "$# matches: $*"
  backup_dir="$1"
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
  mkdir -p "$sb/home/agents"
  printf 'mine\n' >"$sb/home/agents/a.md"
  ln -s "$sb/repo/claude/agents/gone.md" "$sb/home/agents/gone.md"
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

t_backup() {
  mkdir -p "$sb/home/agents"
  printf 'mine\n' >"$sb/home/agents/a.md"
  run_install
  assert_status 0
  set -- "$sb"/home/backups/harness-*
  [ "$#" -eq 1 ] && [ -d "$1" ] || fail "exactly one directory home/backups/harness-*" "$# matches: $*"
  assert_file_content "$1/a.md" "mine"
  assert_link "$sb/home/agents/a.md" "$sb/repo/claude/agents/a.md"
  assert_output_contains "linked=5 unchanged=0 backed_up=1 pruned=0"
}

t_prune() {
  mkdir -p "$sb/home/skills"
  ln -s "$sb/repo/claude/skills/s2" "$sb/home/skills/s2"
  rm -r "$sb/repo/claude/skills/s2"
  mkdir -p "$sb/home/agents"
  ln -s "$sb/repo/claude/agents/gone.md" "$sb/home/agents/gone.md"
  run_install
  assert_status 0
  assert_not_exists "$sb/home/skills/s2"
  assert_not_exists "$sb/home/agents/gone.md"
  assert_output_contains "linked=4 unchanged=0 backed_up=0 pruned=2"
}

t_prune_foreign() {
  mkdir -p "$sb/home/skills"
  ln -s "$sb/repo/claude-other/foreign" "$sb/home/skills/foreign"
  run_install
  assert_status 0
  assert_link "$sb/home/skills/foreign" "$sb/repo/claude-other/foreign"
  assert_output_contains "linked=5 unchanged=0 backed_up=0 pruned=0"
}

t_settings_add_remove() {
  home_settings '{"theme":"dark","permissions":{"deny":["Read(./mine)"]}}'
  frag 10-a.json '{"permissions":{"deny":["Read(./ours)"]}}'
  run_install
  assert_status 0
  assert_json "$sb/home/settings.json" '.theme == "dark" and (.permissions.deny | index("Read(./mine)") != null and index("Read(./ours)") != null)'
  rm "$sb/repo/claude/settings.d/10-a.json"
  run_install
  assert_status 0
  assert_json "$sb/home/settings.json" '.theme == "dark" and .permissions.deny == ["Read(./mine)"]'
  assert_not_exists "$sb/home/.ai-harness-managed.json"
}

t_settings_foreign_equal_kept() {
  home_settings '{"permissions":{"deny":["Read(./same)"]}}'
  frag 10-a.json '{"permissions":{"deny":["Read(./same)"]}}'
  run_install
  assert_status 0
  assert_json "$sb/home/settings.json" '.permissions.deny == ["Read(./same)"]'
  assert_not_exists "$sb/home/.ai-harness-managed.json"
  rm "$sb/repo/claude/settings.d/10-a.json"
  run_install
  assert_status 0
  assert_json "$sb/home/settings.json" '.permissions.deny == ["Read(./same)"]'
}

t_settings_hook_element() {
  home_settings '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"mine.sh"}]}]}}'
  frag 10-a.json '{"hooks":{"PreToolUse":[{"matcher":"mcp__x__.*","hooks":[{"type":"command","command":"ours.sh"}]}]}}'
  run_install
  assert_status 0
  assert_json "$sb/home/settings.json" '.hooks.PreToolUse | map(.matcher) == ["Bash","mcp__x__.*"]'
  frag 10-a.json '{}'
  run_install
  assert_status 0
  assert_json "$sb/home/settings.json" '.hooks.PreToolUse | map(.matcher) == ["Bash"]'
}

t_settings_merge_order() {
  frag 20-b.json '{"model":"b","permissions":{"deny":["B"]}}'
  frag 10-a.json '{"model":"a","permissions":{"deny":["A"]}}'
  run_install
  assert_status 0
  assert_json "$sb/home/settings.json" '.model == "b" and .permissions.deny == ["A","B"]'
}

t_settings_scalar_restore() {
  home_settings '{"model":"opus"}'
  frag 10-a.json '{"model":"sonnet","effortLevel":"x"}'
  run_install
  assert_status 0
  assert_json "$sb/home/settings.json" '.model == "sonnet" and .effortLevel == "x"'
  rm "$sb/repo/claude/settings.d/10-a.json"
  run_install
  assert_status 0
  assert_json "$sb/home/settings.json" '.model == "opus" and (has("effortLevel") | not)'
}

t_settings_scalar_user_changed() {
  home_settings '{"model":"opus"}'
  frag 10-a.json '{"model":"sonnet"}'
  run_install
  assert_status 0
  assert_json "$sb/home/settings.json" '.model == "sonnet"'
  jq '.model = "haiku"' "$sb/home/settings.json" >"$sb/edited.json"
  cp "$sb/edited.json" "$sb/home/settings.json"
  rm "$sb/repo/claude/settings.d/10-a.json"
  run_install
  assert_status 0
  assert_json "$sb/home/settings.json" '.model == "haiku"'
}

t_settings_idempotent() {
  home_settings '{"theme":"dark"}'
  frag 10-a.json '{"permissions":{"deny":["Read(./ours)"]},"model":"sonnet"}'
  run_install
  assert_status 0
  snapshot "$sb/home" "$sb/snapshot.before"
  run_install
  assert_status 0
  assert_tree_unchanged "$sb/home" "$sb/snapshot.before"
  assert_output_contains "settings=unchanged"
}

t_settings_dry_run() {
  home_settings '{"permissions":{"deny":["Read(./mine)"]}}'
  frag 10-a.json '{"permissions":{"deny":["Read(./brand-new)"]}}'
  snapshot "$sb/home" "$sb/snapshot.before"
  run_install --dry-run
  assert_status 0
  assert_tree_unchanged "$sb/home" "$sb/snapshot.before"
  assert_output_contains "+      \"Read(./brand-new)\""
}

t_settings_broken_json() {
  printf '{"theme":' >"$sb/home/settings.json"
  cp "$sb/home/settings.json" "$sb/settings.copy"
  frag 10-a.json '{"model":"sonnet"}'
  run_install
  [ "$status" -ne 0 ] || fail "non-zero exit status" "exit status 0"
  cmp -s "$sb/home/settings.json" "$sb/settings.copy" || fail "settings.json byte-identical" "changed"
  assert_not_exists "$sb/home/.ai-harness-managed.json"
  assert_not_exists "$sb/home/agents"
}

t_settings_broken_fragment() {
  home_settings '{"theme":"dark"}'
  cp "$sb/home/settings.json" "$sb/settings.copy"
  frag 10-a.json '{"model":'
  run_install
  [ "$status" -ne 0 ] || fail "non-zero exit status" "exit status 0"
  cmp -s "$sb/home/settings.json" "$sb/settings.copy" || fail "settings.json byte-identical" "changed"
  assert_not_exists "$sb/home/agents"
}

t_settings_backup() {
  home_settings '{"theme":"dark"}'
  frag 10-a.json '{"model":"sonnet"}'
  run_install
  assert_status 0
  assert_one_backup_dir
  assert_json "$backup_dir/settings.json" '. == {"theme":"dark"}'
}

t_settings_no_temp_left() {
  home_settings '{"theme":"dark"}'
  frag 10-a.json '{"model":"sonnet"}'
  run_install
  assert_status 0
  set -- "$sb"/home/.settings.json.* "$sb"/home/.ai-harness-managed.json.*
  [ ! -e "$1" ] && [ ! -e "$2" ] || fail "no temp files in home" "$*"
  assert_json "$sb/home/.ai-harness-managed.json" '.version == 1'
}

t_settings_created_containers_removed() {
  home_settings '{"theme":"dark"}'
  frag 10-a.json '{"permissions":{"deny":["Read(./ours)"]}}'
  run_install
  assert_status 0
  rm "$sb/repo/claude/settings.d/10-a.json"
  run_install
  assert_status 0
  assert_json "$sb/home/settings.json" '. == {"theme":"dark"}'
}

t_settings_fragments_dedupe() {
  frag 10-a.json '{"permissions":{"deny":["X","Y"]}}'
  frag 20-b.json '{"permissions":{"deny":["Y","Z"]}}'
  run_install
  assert_status 0
  assert_json "$sb/home/settings.json" '.permissions.deny == ["X","Y","Z"]'
}

t_settings_owner_duplicate_survives() {
  home_settings '{"theme":"dark"}'
  frag 10-a.json '{"permissions":{"deny":["Read(./ours)"]}}'
  run_install
  assert_status 0
  jq '.permissions.deny += ["Read(./ours)"]' "$sb/home/settings.json" >"$sb/edited.json"
  cp "$sb/edited.json" "$sb/home/settings.json"
  rm "$sb/repo/claude/settings.d/10-a.json"
  run_install
  assert_status 0
  assert_json "$sb/home/settings.json" '.permissions.deny == ["Read(./ours)"]'
}

t_settings_crash_between_writes() {
  frag 10-a.json '{"permissions":{"deny":["Read(./a)"]}}'
  run_install
  assert_status 0
  frag 10-a.json '{"permissions":{"deny":["Read(./a)","Read(./b)"]}}'
  awk '{print} /echo "  merge   \$SETTINGS"/{print "kill -9 $$"}' "$INSTALL_SH" >"$sb/repo/install.sh"
  { run_install; } 2>/dev/null
  assert_status 137
  assert_json "$sb/home/settings.json" '.permissions.deny == ["Read(./a)","Read(./b)"]'
  cp "$INSTALL_SH" "$sb/repo/install.sh"
  frag 10-a.json '{"permissions":{"deny":["Read(./a)"]}}'
  run_install
  assert_status 0
  assert_json "$sb/home/settings.json" '.permissions.deny == ["Read(./a)"]'
}

t_hook_link() {
  mkdir -p "$sb/repo/claude/hooks" "$sb/home/hooks"
  printf '#!/bin/sh\n' >"$sb/repo/claude/hooks/h.sh"
  printf 'own\n' >"$sb/home/hooks/own.sh"
  run_install
  assert_status 0
  assert_link "$sb/home/hooks/h.sh" "$sb/repo/claude/hooks/h.sh"
  rm "$sb/repo/claude/hooks/h.sh"
  run_install
  assert_status 0
  assert_not_exists "$sb/home/hooks/h.sh"
  assert_file_content "$sb/home/hooks/own.sh" "own"
  assert_output_contains "pruned=1"
}

t_hook_backup() {
  mkdir -p "$sb/repo/claude/hooks" "$sb/home/hooks"
  printf '#!/bin/sh\n' >"$sb/repo/claude/hooks/h.sh"
  printf 'mine\n' >"$sb/home/hooks/h.sh"
  run_install
  assert_status 0
  assert_one_backup_dir
  assert_file_content "$backup_dir/h.sh" "mine"
  assert_link "$sb/home/hooks/h.sh" "$sb/repo/claude/hooks/h.sh"
}

git_repo() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$sb/repo" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@" >/dev/null 2>&1
}

run_install_no_home() {
  status=0
  checkout=$1
  shift
  env -u CLAUDE_HOME HOME="$sb/user" bash "$checkout/install.sh" "$@" >"$sb/out" 2>&1 || status=$?
}

t_worktree_refused_without_claude_home() {
  mkdir -p "$sb/user"
  git_repo init -q
  git_repo add -A
  git_repo commit -q -m init
  git_repo worktree add -q "$sb/wt" -b wt
  run_install_no_home "$sb/wt"
  assert_status 1
  assert_output_contains "run install.sh from the main checkout"
  assert_not_exists "$sb/user/.claude"
}

t_worktree_allowed_with_claude_home() {
  git_repo init -q
  git_repo add -A
  git_repo commit -q -m init
  git_repo worktree add -q "$sb/wt" -b wt
  status=0
  CLAUDE_HOME="$sb/home" HOME="$sb" bash "$sb/wt/install.sh" >"$sb/out" 2>&1 || status=$?
  assert_status 0
  assert_link "$sb/home/CLAUDE.md" "$sb/wt/claude/CLAUDE.md"
}

t_main_checkout_installs_without_claude_home() {
  mkdir -p "$sb/user"
  git_repo init -q
  git_repo add -A
  git_repo commit -q -m init
  run_install_no_home "$sb/repo"
  assert_status 0
  assert_link "$sb/user/.claude/CLAUDE.md" "$sb/repo/claude/CLAUDE.md"
}

t_non_git_copy_installs_without_claude_home() {
  mkdir -p "$sb/user"
  run_install_no_home "$sb/repo"
  assert_status 0
  assert_link "$sb/user/.claude/CLAUDE.md" "$sb/repo/claude/CLAUDE.md"
}

t_worktree_dry_run_refused_without_claude_home() {
  mkdir -p "$sb/user"
  git_repo init -q
  git_repo add -A
  git_repo commit -q -m init
  git_repo worktree add -q "$sb/wt" -b wt
  status=0
  env -u CLAUDE_HOME HOME="$sb/user" bash "$sb/wt/install.sh" --dry-run >"$sb/out" 2>&1 || status=$?
  assert_status 1
}

t_manifest_wrong_version() {
  frag a.json '{"a":1}'
  run_install
  assert_status 0
  printf '%s\n' '{"version":2,"scalars":[],"elements":[],"created":[]}' >"$sb/home/.ai-harness-managed.json"
  snapshot "$sb/home" "$sb/snapshot.before"
  run_install
  assert_status 1
  assert_output_contains "manifest"
  assert_tree_unchanged "$sb/home" "$sb/snapshot.before"
}

t_manifest_non_array_field() {
  frag a.json '{"a":1}'
  run_install
  assert_status 0
  printf '%s\n' '{"version":1,"scalars":{},"elements":[],"created":[]}' >"$sb/home/.ai-harness-managed.json"
  snapshot "$sb/home" "$sb/snapshot.before"
  run_install
  assert_status 1
  assert_output_contains "manifest"
  assert_tree_unchanged "$sb/home" "$sb/snapshot.before"
}

t_manifest_missing_field() {
  frag a.json '{"a":1}'
  run_install
  printf '%s\n' '{"version":1,"scalars":[],"elements":[]}' >"$sb/home/.ai-harness-managed.json"
  run_install
  assert_status 1
  assert_output_contains "manifest"
}

t_manifest_valid_schema_accepted() {
  frag a.json '{"a":1}'
  run_install
  assert_status 0
  run_install
  assert_status 0
  assert_json "$sb/home/settings.json" '.a == 1'
}

passed=0
total=0
for SCENARIO in link unchanged dry-run bad-arg backup prune prune-foreign settings-add-remove settings-foreign-equal-kept settings-hook-element settings-merge-order settings-scalar-restore settings-scalar-user-changed settings-idempotent settings-dry-run settings-broken-json settings-broken-fragment settings-backup settings-no-temp-left settings-created-containers-removed settings-fragments-dedupe settings-owner-duplicate-survives settings-crash-between-writes hook-link hook-backup worktree-refused-without-claude-home worktree-allowed-with-claude-home main-checkout-installs-without-claude-home non-git-copy-installs-without-claude-home worktree-dry-run-refused-without-claude-home manifest-wrong-version manifest-non-array-field manifest-missing-field manifest-valid-schema-accepted; do
  total=$((total + 1))
  fn="t_$(printf '%s' "$SCENARIO" | tr - _)"
  set +e
  ( set -e; sandbox; "$fn" )
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    passed=$((passed + 1))
    printf 'ok %s\n' "$SCENARIO"
  elif [ "$rc" -ne 70 ]; then
    printf 'FAIL %s: setup and commands succeed / exit status %s\n' "$SCENARIO" "$rc"
  fi
done

printf '%s/%s passed\n' "$passed" "$total"
[ "$passed" -eq "$total" ] || exit 1
