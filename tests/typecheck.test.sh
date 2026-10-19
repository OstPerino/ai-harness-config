#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/claude/hooks/typecheck.sh"
FRAGMENT="$ROOT/claude/settings.d/30-quality.json"
INSTALL_SH="$ROOT/install.sh"
SH_BIN="${SH:-sh}"

SCENARIO=""
sb=""
out=""
status=0

sandbox() {
  sb=$(mktemp -d "${TMPDIR:-/tmp}/typecheck-test.XXXXXX") || exit 1
  [ -n "$sb" ] && [ -d "$sb" ] || exit 1
  sb=$(cd "$sb" && pwd) || exit 1
  case "${sb##*/}" in
    typecheck-test.??????) ;;
    *) exit 1 ;;
  esac
  trap 'rm -rf "${sb:?}"' EXIT
  mkdir -p "$sb/bin" "$sb/tmp"
  real_git=$(command -v git) || exit 1
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_git" >"$sb/bin/git"
  chmod +x "$sb/bin/git"
}

fail() {
  printf 'FAIL %s: %s / %s\n' "$SCENARIO" "$1" "$2"
  exit 70
}

mkfake() {
  fake_name="$1"
  fake_code="$2"
  fake_src="${3:-}"
  {
    printf '#!/bin/sh\n'
    printf 'printf "%%s %%s %%s\\n" "%s" "$(pwd)" "$*" >>"%s/calls"\n' "$fake_name" "$sb"
    if [ -n "$fake_src" ]; then
      printf 'cat "%s"\n' "$fake_src"
    else
      printf 'printf "fake-out-1\\nfake-out-2\\nfake-out-3\\n"\n'
    fi
    printf 'printf "fake-err-%s\\n" >&2\n' "$fake_name"
    printf 'exit %s\n' "$fake_code"
  } >"$sb/bin/$fake_name"
  chmod +x "$sb/bin/$fake_name"
}

mkproj() {
  mkdir -p "$1/.git" "$1/src"
}

touchf() {
  mkdir -p "$(dirname "$1")"
  printf 'x\n' >"$1"
}

runhook() {
  status=0
  out=$(printf '%s' "$1" | env PATH="$sb/bin:/usr/bin:/bin" TMPDIR="$sb/tmp" "$SH_BIN" "$HOOK" 2>"$sb/err") || status=$?
}

call() {
  runhook "$(jq -n --arg t "${2:-Edit}" --arg f "$1" --arg c "$sb" '{tool_name:$t,tool_input:{file_path:$f},cwd:$c}')"
}

assert_stdout_empty() {
  [ -z "$out" ] || fail "empty stdout" "$out"
}

assert_silent() {
  [ "$status" -eq 0 ] || fail "exit 0" "exit $status"
  assert_stdout_empty
  [ ! -s "$sb/err" ] || fail "empty stderr" "$(cat "$sb/err")"
}

assert_no_calls() {
  [ ! -e "$sb/calls" ] || fail "no tool calls" "$(cat "$sb/calls")"
}

assert_calls() {
  [ -f "$sb/calls" ] || fail "calls: $1" "no calls"
  actual=$(cat "$sb/calls")
  [ "$actual" = "$1" ] || fail "calls: $1" "$actual"
}

assert_blocked() {
  [ "$status" -eq 2 ] || fail "exit 2" "exit $status"
  assert_stdout_empty
  first=$(head -n 1 "$sb/err")
  [ "$first" = "$1" ] || fail "header $1" "$first"
}

assert_err_contains() {
  grep -F -- "$1" "$sb/err" >/dev/null 2>&1 || fail "stderr contains '$1'" "$(cat "$sb/err")"
}

t_ts_error_full_output() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/tsconfig.json"
  touchf "$p/src/a.ts"
  mkfake tsc 2
  call "$p/src/a.ts"
  assert_blocked "typecheck: tsc failed in $p (exit 2)"
  assert_err_contains "fake-out-1"
  assert_err_contains "fake-out-2"
  assert_err_contains "fake-out-3"
  assert_err_contains "fake-err-tsc"
  assert_calls "tsc $p --noEmit"
}

t_ts_clean_silent() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/tsconfig.json"
  touchf "$p/src/a.ts"
  mkfake tsc 0
  call "$p/src/a.ts"
  assert_silent
  assert_calls "tsc $p --noEmit"
}

t_vue_uses_vue_tsc() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/tsconfig.json"
  touchf "$p/src/App.vue"
  printf '{"devDependencies":{"vue":"3.0.0"}}\n' >"$p/package.json"
  mkfake tsc 1
  mkfake vue-tsc 1
  call "$p/src/App.vue"
  assert_blocked "typecheck: vue-tsc failed in $p (exit 1)"
  assert_calls "vue-tsc $p --noEmit"
}

t_vue_dependency_in_dependencies() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/tsconfig.json"
  touchf "$p/src/a.ts"
  printf '{"dependencies":{"vue":"3.0.0"}}\n' >"$p/package.json"
  mkfake tsc 1
  mkfake vue-tsc 1
  call "$p/src/a.ts"
  assert_calls "vue-tsc $p --noEmit"
}

t_ts_without_vue_uses_tsc() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/tsconfig.json"
  touchf "$p/src/a.ts"
  printf '{"dependencies":{"left-pad":"1.0.0"}}\n' >"$p/package.json"
  mkfake tsc 1
  mkfake vue-tsc 1
  call "$p/src/a.ts"
  assert_calls "tsc $p --noEmit"
}

t_cargo_error_full_output() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/Cargo.toml"
  touchf "$p/src/main.rs"
  mkfake cargo 101
  call "$p/src/main.rs"
  assert_blocked "typecheck: cargo failed in $p (exit 101)"
  assert_err_contains "fake-out-1"
  assert_err_contains "fake-out-3"
  assert_err_contains "fake-err-cargo"
  assert_calls "cargo $p check"
}

t_cargo_clean_silent() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/Cargo.toml"
  touchf "$p/src/main.rs"
  mkfake cargo 0
  call "$p/src/main.rs"
  assert_silent
  assert_calls "cargo $p check"
}

t_nearest_tsconfig_wins() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/tsconfig.json"
  touchf "$p/packages/a/tsconfig.json"
  touchf "$p/packages/a/src/x.ts"
  mkfake tsc 1
  call "$p/packages/a/src/x.ts"
  assert_calls "tsc $p/packages/a --noEmit"
}

t_nearest_cargo_wins() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/Cargo.toml"
  touchf "$p/crates/c/Cargo.toml"
  touchf "$p/crates/c/src/lib.rs"
  mkfake cargo 1
  call "$p/crates/c/src/lib.rs"
  assert_calls "cargo $p/crates/c check"
}

t_non_code_file_skipped() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/tsconfig.json"
  touchf "$p/README.md"
  touchf "$p/notes.json"
  mkfake tsc 1
  call "$p/README.md"
  assert_silent
  call "$p/notes.json"
  assert_silent
  assert_no_calls
}

t_no_project_silent() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/src/a.ts"
  mkfake tsc 1
  call "$p/src/a.ts"
  assert_silent
  assert_no_calls
}

t_search_stops_at_git_root() {
  touchf "$sb/tsconfig.json"
  p="$sb/p"
  mkproj "$p"
  touchf "$p/src/a.ts"
  mkfake tsc 1
  call "$p/src/a.ts"
  assert_silent
  assert_no_calls
  rm -rf "$p/.git"
  printf 'gitdir: /elsewhere\n' >"$p/.git"
  call "$p/src/a.ts"
  assert_silent
  assert_no_calls
}

t_long_output_not_truncated() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/tsconfig.json"
  touchf "$p/src/a.ts"
  awk 'BEGIN { for (i = 1; i <= 3000; i++) printf "src/f%05d.ts(1,1): error TS2322: unique message number %05d with filler xxxxxxxxxxxxxxxx\n", i, i }' >"$sb/long"
  [ "$(wc -c <"$sb/long" | tr -d ' ')" -gt 100000 ] || fail "fixture over 100000 bytes" "too small"
  mkfake tsc 1 "$sb/long"
  call "$p/src/a.ts"
  assert_blocked "typecheck: tsc failed in $p (exit 1)"
  { cat "$sb/long"; printf 'fake-err-tsc\n'; } >"$sb/expected"
  tail -n +2 "$sb/err" >"$sb/body"
  cmp "$sb/expected" "$sb/body" >/dev/null 2>&1 || fail "stderr body equals full tool output" "differs: $(wc -l <"$sb/body") lines"
  last=$(tail -n 2 "$sb/err" | head -n 1)
  case "$last" in
    *"number 03000"*) ;;
    *) fail "last tool line present" "$last" ;;
  esac
}

t_tool_missing_silent() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/tsconfig.json"
  touchf "$p/src/a.ts"
  call "$p/src/a.ts"
  assert_silent
  assert_no_calls
}

t_local_bin_preferred() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/tsconfig.json"
  touchf "$p/src/a.ts"
  mkdir -p "$p/node_modules/.bin"
  {
    printf '#!/bin/sh\n'
    printf 'printf "local\\n" >>"%s/calls"\n' "$sb"
    printf 'exit 1\n'
  } >"$p/node_modules/.bin/tsc"
  chmod +x "$p/node_modules/.bin/tsc"
  mkfake tsc 1
  call "$p/src/a.ts"
  assert_calls "local"
}

gitrepo() {
  repo_dir=$1
  shift
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$repo_dir" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@" >/dev/null 2>&1
}

mklocal() {
  mkdir -p "$1/node_modules/.bin"
  {
    printf '#!/bin/sh\n'
    printf 'printf "local\\n" >>"%s/calls"\n' "$sb"
    printf 'exit 1\n'
  } >"$1/node_modules/.bin/tsc"
  chmod +x "$1/node_modules/.bin/tsc"
}

t_tracked_bin_not_run() {
  p="$sb/p"
  mkdir -p "$p"
  touchf "$p/tsconfig.json"
  touchf "$p/src/a.ts"
  mklocal "$p"
  gitrepo "$p" init -q
  gitrepo "$p" add -f -A
  gitrepo "$p" commit -q -m init
  mkfake tsc 1
  call "$p/src/a.ts"
  assert_calls "tsc $p --noEmit"
}

t_tracked_hoisted_bin_not_run() {
  p="$sb/p"
  mkdir -p "$p"
  touchf "$p/packages/a/tsconfig.json"
  touchf "$p/packages/a/src/x.ts"
  mklocal "$p"
  gitrepo "$p" init -q
  gitrepo "$p" add -f -A
  gitrepo "$p" commit -q -m init
  mkfake tsc 1
  call "$p/packages/a/src/x.ts"
  assert_calls "tsc $p/packages/a --noEmit"
}

t_untracked_bin_in_git_repo_runs() {
  p="$sb/p"
  mkdir -p "$p"
  touchf "$p/tsconfig.json"
  touchf "$p/src/a.ts"
  gitrepo "$p" init -q
  gitrepo "$p" add -A
  gitrepo "$p" commit -q -m init
  mklocal "$p"
  mkfake tsc 1
  call "$p/src/a.ts"
  assert_calls "local"
}

t_tracked_bin_without_path_tool_silent() {
  p="$sb/p"
  mkdir -p "$p"
  touchf "$p/tsconfig.json"
  touchf "$p/src/a.ts"
  mklocal "$p"
  gitrepo "$p" init -q
  gitrepo "$p" add -f -A
  gitrepo "$p" commit -q -m init
  call "$p/src/a.ts"
  assert_silent
  assert_no_calls
}

t_broken_git_skips_local_bin() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/tsconfig.json"
  touchf "$p/src/a.ts"
  mklocal "$p"
  printf '#!/bin/sh\nexit 69\n' >"$sb/bin/git"
  mkfake tsc 1
  call "$p/src/a.ts"
  assert_calls "tsc $p --noEmit"
}

t_garbage_input_silent() {
  mkfake tsc 1
  runhook 'not json'
  assert_silent
  runhook ''
  assert_silent
  assert_no_calls
}

t_missing_file_silent() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/tsconfig.json"
  mkfake tsc 1
  call "$p/src/gone.ts"
  assert_silent
  assert_no_calls
}

t_path_with_spaces() {
  p="$sb/my proj"
  mkproj "$p"
  touchf "$p/tsconfig.json"
  touchf "$p/src/a.ts"
  mkfake tsc 1
  call "$p/src/a.ts"
  assert_blocked "typecheck: tsc failed in $p (exit 1)"
  assert_calls "tsc $p --noEmit"
}

t_solution_tsconfig_uses_build() {
  p="$sb/p"
  mkproj "$p"
  printf '{"files":[],"references":[{"path":"./a"}]}\n' >"$p/tsconfig.json"
  touchf "$p/src/a.ts"
  mkfake tsc 1
  call "$p/src/a.ts"
  assert_calls "tsc $p -b --noEmit"
}

t_solution_tsconfig_vue_uses_build() {
  p="$sb/p"
  mkproj "$p"
  printf '{"files":[],"references":[{"path":"./a"}]}\n' >"$p/tsconfig.json"
  printf '{"devDependencies":{"vue":"3.0.0"}}\n' >"$p/package.json"
  touchf "$p/src/a.ts"
  mkfake vue-tsc 1
  call "$p/src/a.ts"
  assert_calls "vue-tsc $p --build --noEmit"
}

t_empty_or_broken_references_plain() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/src/a.ts"
  mkfake tsc 0
  printf '{"references":[]}\n' >"$p/tsconfig.json"
  call "$p/src/a.ts"
  assert_calls "tsc $p --noEmit"
  rm "$sb/calls"
  printf '{\n  // jsonc\n  "references": [{"path": "./a"}]\n}\n' >"$p/tsconfig.json"
  call "$p/src/a.ts"
  assert_calls "tsc $p --noEmit"
}

t_hoisted_bin_found() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/packages/a/tsconfig.json"
  touchf "$p/packages/a/src/x.ts"
  mkdir -p "$p/node_modules/.bin"
  {
    printf '#!/bin/sh\n'
    printf 'printf "hoisted\\n" >>"%s/calls"\n' "$sb"
    printf 'exit 1\n'
  } >"$p/node_modules/.bin/tsc"
  chmod +x "$p/node_modules/.bin/tsc"
  call "$p/packages/a/src/x.ts"
  assert_calls "hoisted"
}

t_bin_above_git_ignored() {
  mkdir -p "$sb/node_modules/.bin"
  {
    printf '#!/bin/sh\n'
    printf 'printf "outside\\n" >>"%s/calls"\n' "$sb"
    printf 'exit 1\n'
  } >"$sb/node_modules/.bin/tsc"
  chmod +x "$sb/node_modules/.bin/tsc"
  p="$sb/p"
  mkproj "$p"
  touchf "$p/tsconfig.json"
  touchf "$p/src/a.ts"
  call "$p/src/a.ts"
  assert_silent
  assert_no_calls
}

t_package_json_above_git_ignored() {
  printf '{"devDependencies":{"vue":"3.0.0"}}\n' >"$sb/package.json"
  p="$sb/p"
  mkproj "$p"
  touchf "$p/tsconfig.json"
  touchf "$p/src/a.ts"
  mkfake tsc 1
  mkfake vue-tsc 1
  call "$p/src/a.ts"
  assert_calls "tsc $p --noEmit"
}

t_peer_vue_tsc_uses_vue_tsc() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/tsconfig.json"
  touchf "$p/src/a.ts"
  printf '{"peerDependencies":{"vue-tsc":"2.0.0"}}\n' >"$p/package.json"
  mkfake tsc 1
  mkfake vue-tsc 1
  call "$p/src/a.ts"
  assert_calls "vue-tsc $p --noEmit"
}

t_ts_extensions_checked() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/tsconfig.json"
  mkfake tsc 0
  for f in src/a.ts src/a.tsx src/a.mts src/a.cts src/a.vue tsconfig.json; do
    touchf "$p/$f"
    rm -f "$sb/calls"
    call "$p/$f"
    [ -f "$sb/calls" ] || fail "tsc called for $f" "no calls"
  done
}

t_rust_extensions_checked() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/Cargo.toml"
  touchf "$p/src/lib.rs"
  mkfake cargo 0
  for f in src/lib.rs Cargo.toml; do
    rm -f "$sb/calls"
    call "$p/$f"
    [ -f "$sb/calls" ] || fail "cargo called for $f" "no calls"
  done
}

t_cargo_missing_silent() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/Cargo.toml"
  touchf "$p/src/main.rs"
  call "$p/src/main.rs"
  assert_silent
  assert_no_calls
}

t_repeated_output_silent() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/tsconfig.json"
  touchf "$p/src/a.ts"
  mkfake tsc 1
  call "$p/src/a.ts"
  assert_blocked "typecheck: tsc failed in $p (exit 1)"
  call "$p/src/a.ts"
  assert_silent
  assert_calls "tsc $p --noEmit
tsc $p --noEmit"
}

t_changed_output_blocks() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/tsconfig.json"
  touchf "$p/src/a.ts"
  mkfake tsc 1
  call "$p/src/a.ts"
  assert_blocked "typecheck: tsc failed in $p (exit 1)"
  printf 'other error\n' >"$sb/other"
  mkfake tsc 1 "$sb/other"
  call "$p/src/a.ts"
  assert_blocked "typecheck: tsc failed in $p (exit 1)"
  assert_err_contains "other error"
  call "$p/src/a.ts"
  assert_silent
}

t_clean_run_resets_dedupe() {
  p="$sb/p"
  mkproj "$p"
  touchf "$p/tsconfig.json"
  touchf "$p/src/a.ts"
  mkfake tsc 1
  call "$p/src/a.ts"
  assert_blocked "typecheck: tsc failed in $p (exit 1)"
  mkfake tsc 0
  call "$p/src/a.ts"
  assert_silent
  mkfake tsc 1
  call "$p/src/a.ts"
  assert_blocked "typecheck: tsc failed in $p (exit 1)"
}

t_dedupe_is_per_directory() {
  mkproj "$sb/p"
  mkproj "$sb/q"
  touchf "$sb/p/tsconfig.json"
  touchf "$sb/p/src/a.ts"
  touchf "$sb/q/tsconfig.json"
  touchf "$sb/q/src/a.ts"
  mkfake tsc 1
  call "$sb/p/src/a.ts"
  assert_blocked "typecheck: tsc failed in $sb/p (exit 1)"
  call "$sb/q/src/a.ts"
  assert_blocked "typecheck: tsc failed in $sb/q (exit 1)"
}

t_hook_executable() {
  [ -x "$HOOK" ] || fail "hook executable" "not executable: $HOOK"
  [ "$(head -n 1 "$HOOK")" = "#!/bin/sh" ] || fail "starts with #!/bin/sh" "$(head -n 1 "$HOOK")"
}

install_sandbox() {
  mkdir -p "$sb/repo/claude/agents" "$sb/repo/claude/settings.d" "$sb/home"
  cp "$INSTALL_SH" "$sb/repo/install.sh"
  printf 'a\n' >"$sb/repo/claude/agents/a.md"
  printf 'claude\n' >"$sb/repo/claude/CLAUDE.md"
  cp "$FRAGMENT" "$sb/repo/claude/settings.d/30-quality.json"
}

run_install() {
  status=0
  CLAUDE_HOME="$sb/home" HOME="$sb" bash "$sb/repo/install.sh" >"$sb/install.out" 2>&1 || status=$?
  [ "$status" -eq 0 ] || fail "install exit 0" "exit $status: $(tail -n 3 "$sb/install.out")"
}

assert_settings() {
  jq -e "$1" "$sb/home/settings.json" >/dev/null 2>&1 || fail "settings match jq $1" "$(cat "$sb/home/settings.json")"
}

t_quality_fragment_disables_lsp() {
  install_sandbox
  printf '%s\n' '{"enabledPlugins":{"typescript-lsp@claude-plugins-official":true,"rust-analyzer-lsp@claude-plugins-official":true,"other@x":true}}' >"$sb/home/settings.json"
  run_install
  assert_settings '.enabledPlugins["typescript-lsp@claude-plugins-official"] == false'
  assert_settings '.enabledPlugins["rust-analyzer-lsp@claude-plugins-official"] == false'
  assert_settings '.enabledPlugins["other@x"] == true'
  assert_settings '[.hooks.PostToolUse[] | select(.matcher == "Edit|Write|MultiEdit") | .hooks[] | select(.command == "~/.claude/hooks/typecheck.sh" and (.timeout | type) == "number")] | length == 1'
}

t_quality_fragment_restores_plugins() {
  install_sandbox
  printf '%s\n' '{"enabledPlugins":{"typescript-lsp@claude-plugins-official":true,"rust-analyzer-lsp@claude-plugins-official":true,"other@x":true}}' >"$sb/home/settings.json"
  run_install
  rm "$sb/repo/claude/settings.d/30-quality.json"
  run_install
  assert_settings '.enabledPlugins["typescript-lsp@claude-plugins-official"] == true'
  assert_settings '.enabledPlugins["rust-analyzer-lsp@claude-plugins-official"] == true'
  assert_settings '.enabledPlugins["other@x"] == true'
  assert_settings '((.hooks // {}) | has("PostToolUse")) | not'
}

t_quality_fragment_removes_absent_plugin_keys() {
  install_sandbox
  printf '%s\n' '{"enabledPlugins":{"other@x":true}}' >"$sb/home/settings.json"
  run_install
  assert_settings '.enabledPlugins["typescript-lsp@claude-plugins-official"] == false'
  rm "$sb/repo/claude/settings.d/30-quality.json"
  run_install
  assert_settings '.enabledPlugins | has("typescript-lsp@claude-plugins-official") or has("rust-analyzer-lsp@claude-plugins-official") | not'
  assert_settings '.enabledPlugins["other@x"] == true'
}

passed=0
total=0
for SCENARIO in ts-error-full-output ts-clean-silent vue-uses-vue-tsc vue-dependency-in-dependencies ts-without-vue-uses-tsc cargo-error-full-output cargo-clean-silent nearest-tsconfig-wins nearest-cargo-wins non-code-file-skipped no-project-silent search-stops-at-git-root long-output-not-truncated tool-missing-silent local-bin-preferred tracked-bin-not-run tracked-hoisted-bin-not-run untracked-bin-in-git-repo-runs tracked-bin-without-path-tool-silent broken-git-skips-local-bin garbage-input-silent missing-file-silent path-with-spaces solution-tsconfig-uses-build solution-tsconfig-vue-uses-build empty-or-broken-references-plain hoisted-bin-found bin-above-git-ignored package-json-above-git-ignored peer-vue-tsc-uses-vue-tsc ts-extensions-checked rust-extensions-checked cargo-missing-silent repeated-output-silent changed-output-blocks clean-run-resets-dedupe dedupe-is-per-directory hook-executable quality-fragment-disables-lsp quality-fragment-restores-plugins quality-fragment-removes-absent-plugin-keys; do
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
