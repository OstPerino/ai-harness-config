#!/bin/sh
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
input=$(cat)
block() {
  printf 'guard-rm: %s\n' "$1" >&2
  exit 2
}
command -v jq >/dev/null 2>&1 || block 'jq not found, refusing to run'
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty') || block 'cannot parse hook input'
[ -n "$tool" ] || block 'empty tool_name'
[ "$tool" = Bash ] || exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty') || block 'cannot parse hook input'
proj=${CLAUDE_PROJECT_DIR:-}
[ -n "$proj" ] || proj=$cwd
roots=''
add_root() {
  r=${1%/}
  [ -n "$r" ] || return 0
  roots="$roots$r
"
  if [ -d "$r" ]; then
    p=$(cd "$r" && pwd -P) && roots="$roots$p
"
  fi
  return 0
}
h=${HOME:-}
h=${h%/}
if [ -z "$h" ] || [ "${proj%/}" != "$h" ]; then add_root "$proj"; fi
add_root "${TMPDIR:-}"
add_root /tmp
add_root /private/tmp
base=$cwd
[ -n "$base" ] || base=${CLAUDE_PROJECT_DIR:-}
prog='
def q: [39] | implode;
def clean: gsub("[" + q + "\"]"; "");
def toks: [splits("[ \t]+")] | map(select(length > 0));
def segs: gsub("\\$\\(|[`()|&;\n]"; "\u0001") | split("\u0001");
def norm: split("/") | reduce .[] as $s ([]; if $s == "" or $s == "." then . elif $s == ".." then .[:-1] else . + [$s] end) | "/" + join("/");
def unredir: . as $t | [range(0; length) as $i | select(($t[$i] | test("^[0-9&]*>") | not) and ($i == 0 or ($t[$i - 1] | test("^[0-9&]*>{1,2}[|]?$") | not))) | $t[$i]];
def unq: if test("^\"[^\"$`\\\\" + q + "]*\"$") or test("^" + q + "[^\"$`\\\\" + q + "]*" + q + "$") then .[1:-1] else . end;
def inside($p; $R): any($R[]; . as $r | $p | startswith($r + "/"));
def rmidx($t): [range(0; $t | length) | select(($t[.] | test("^[\\\\" + q + "\"]*(.*/)?rm[" + q + "\"]*$"; "i")) and (. == 0 or ($t[. - 1] | ascii_downcase) != "git"))];
def verdict($w; $cd; $home; $base; $R):
  if $w == "" then "empty target"
  elif ($w | test("[$`\"\\\\{}" + q + "]")) then "unresolvable target " + $w
  elif ($w | test("^~[^/]")) or ($home == "" and ($w | startswith("~"))) then "unresolvable target " + $w
  else
    ($w | if . == "~" then $home elif startswith("~/") then $home + .[1:] else . end) as $e
    | ($e | startswith("/")) as $abs
    | if ($abs | not) and $cd then "relative target after cd: " + $w
      elif ($abs | not) and $base == "" then "relative target, cwd unknown: " + $w
      else
        (if $abs then $e else $base + "/" + $e end) as $full
        | ($full | split("/")) as $parts
        | if ($parts[:-1] | any(test("[*?\\[]"))) then "glob before last segment: " + $w
          elif ($parts[-1] | test("[*?\\[]")) and ($parts[-1] | startswith(".")) then "dotted glob: " + $w
          elif ($parts[-1] | test("[*?\\[]")) then
            (($parts[:-1] | join("/")) | norm) as $par
            | if inside($par; $R) then null else "outside project and temp dirs: " + $w end
          else
            ($full | norm) as $p
            | if inside($p; $R) then null else "outside project and temp dirs: " + $w end
          end
      end
  end;
(.tool_input.command | if type != "string" or length == 0 then error("no command") else . end) as $cmd
| ($roots | split("\n") | map(select(length > 0) | norm)) as $R
| ([$cmd | segs[]]) as $S
| [range(0; $S | length) as $si
   | ($S[$si] | toks) as $t
   | rmidx($t)[] as $i
   | ($t[$i + 1:] | unredir) as $rest
   | ($rest | index("--")) as $dd
   | ($rest | if $dd == null then . else .[:$dd] end) as $pre
   | ($pre | map(select(startswith("-")))) as $flags
   | (($pre | map(select(startswith("-") | not))) + (if $dd == null then [] else $rest[$dd + 1:] end)) as $targets
   | select($flags | any(test("^-[^-]*[rR]") or . == "--recursive"))
   | ((($S[:$si] | map(toks) | flatten) + $t[:$i]) | any(test("^(cd|pushd)$"; "i"))) as $cd
   | if ($targets | length) == 0 then "recursive rm without a resolvable target"
     else ($targets[] | unq | verdict(.; $cd; $home; $base; $R)) end
   | select(. != null)]
| first // ""
'
reason=$(printf '%s' "$input" | jq -r --arg roots "$roots" --arg home "${HOME:-}" --arg base "$base" "$prog") || block 'cannot analyze command'
[ -z "$reason" ] || block "$reason"
exit 0
