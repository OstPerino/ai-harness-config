#!/bin/sh
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
input=$(cat)
block() {
  printf 'guard-write: %s\n' "$1" >&2
  exit 2
}
command -v jq >/dev/null 2>&1 || block 'jq not found, refusing to run'
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty') || block 'cannot parse hook input'
[ -n "$tool" ] || block 'empty tool_name'
case $tool in
  Write|Edit|MultiEdit|NotebookEdit|Bash|mcp__*download*) ;;
  *) exit 0 ;;
esac
home=${HOME:-}
home=${home%/}
[ -n "$home" ] || block 'HOME is not set'
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty') || block 'cannot parse hook input'

files="$home/.claude/settings.json
$home/.claude/.ai-harness-managed.json
$home/.claude.json
"
dirs="$home/.claude/hooks
"
if [ -d "$home" ]; then
  hp=$(cd "$home" && pwd -P) || hp=
  if [ -n "$hp" ] && [ "$hp" != "$home" ]; then
    files="$files$hp/.claude/settings.json
$hp/.claude/.ai-harness-managed.json
$hp/.claude.json
"
    dirs="$dirs$hp/.claude/hooks
"
  fi
fi

cdirs=''
mains=''
add_claude_dir() {
  [ -n "$1" ] || return 0
  cdirs="$cdirs$1
"
  mains="$mains${1%/*}
"
  if [ -d "$1" ]; then
    p=$(cd "$1" && pwd -P) && cdirs="$cdirs$p
" && mains="$mains${p%/*}
"
  fi
  return 0
}
for l in "$home"/.claude/hooks/*.sh; do
  [ -L "$l" ] || continue
  t=$(readlink "$l") || continue
  case $t in /*) ;; *) t=${l%/*}/$t ;; esac
  case $t in
    */claude/hooks/*.sh) d=${t%/*}; add_claude_dir "${d%/*}" ;;
  esac
done
l=$home/.claude/CLAUDE.md
if [ -L "$l" ]; then
  t=$(readlink "$l") || t=
  case $t in /*) ;; *) t=${l%/*}/$t ;; esac
  case $t in
    */claude/CLAUDE.md) add_claude_dir "${t%/*}" ;;
  esac
fi

if [ -n "$cdirs" ]; then
  markers='\.claude/settings|\.claude\.json|\.ai-harness-managed\.json|claude/hooks|claude/settings\.d'
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    dirs="$dirs$c/hooks
$c/settings.d
"
  done <<EOF
$cdirs
EOF
else
  markers='\.claude'
  dirs="$dirs$home/.claude
"
  if [ -n "${hp:-}" ]; then dirs="$dirs$hp/.claude
"; fi
fi

prog='
def q: [39] | implode;
def clean: gsub("[" + q + "\"]"; "");
def toks: [splits("[ \t]+")] | map(select(length > 0));
def base: sub("^.*/"; "") | ascii_downcase;
def segs: gsub(">\\|"; ">") | gsub("\\$\\(|[`()|&;\n]"; "\u0001") | split("\u0001");
def norm: split("/") | reduce .[] as $s ([]; if $s == "" or $s == "." then . elif $s == ".." then .[:-1] else . + [$s] end) | "/" + join("/");
def lines: split("\n") | map(select(length > 0));
def lead($w):
  if length == 0 then .
  elif (.[0] | clean | base | test("^(sudo|doas|env|command|exec|nohup|time|nice|xargs|stdbuf|timeout|builtin)$")) then .[1:] | lead(true)
  elif (.[0] | test("^[A-Za-z_][A-Za-z0-9_]*=")) then .[1:] | lead($w)
  elif $w and (.[0] | test("^-[ugpCDRTUILP]$")) then .[2:] | lead($w)
  elif $w and (.[0] | test("^-[nks]$")) and ((.[1] // "") | test("^[0-9.]+[smhd]?$")) then .[2:] | lead($w)
  elif $w and (.[0] | test("^-")) then .[1:] | lead($w)
  elif $w and (.[0] | test("^[0-9.]+[smhd]?$")) then .[1:] | lead($w)
  else . end;
def resolve($home; $cwd):
  clean
  | if . == "~" or . == "$HOME" or . == "${HOME}" then $home
    elif startswith("~/") then $home + .[1:]
    elif startswith("$HOME/") then $home + .[5:]
    elif startswith("${HOME}/") then $home + .[7:]
    else . end
  | if test("[$`\\\\{}]") or test("^~") then null
    elif startswith("/") then norm
    elif $cwd == "" then null
    else ($cwd + "/" + .) | norm end;
def optdir($short; $long):
  . as $a
  | [range(0; length) as $i | $a[$i] as $x
     | if $x == $short or ($long != "" and $x == $long) then ($a[$i + 1] // empty)
       elif $long != "" and ($x | startswith($long + "=")) then $x[($long | length) + 1:]
       elif ($x | startswith($short)) and ($x | length) > ($short | length) and ($short | length) == 2 then $x[2:]
       else empty end];
def nonflags: map(select(startswith("-") | not));
def tgt($d): map({w: ., d: $d});
def gitrest: if length == 0 then [] elif (.[0] == "-C" or .[0] == "-c") then .[2:] | gitrest elif (.[0] | startswith("-")) then .[1:] | gitrest else . end;
def redirs:
  . as $t
  | [range(0; length) as $i
     | ($t[$i] | capture("^[0-9&]*>{1,2}[|]?(?<r>.*)$")) as $m
     | if $m.r == "" then ($t[$i + 1] // empty) else $m.r end]
  | tgt(false);
def targets($depth):
  lead(false) as $c
  | if ($c | length) == 0 then []
    else ($c[0] | clean | base) as $h | ($c[1:]) as $a
    | if ($h | test("^(sh|bash|zsh|dash|ksh|ash)$")) then
        (($a | map(test("^-[A-Za-z]*c[A-Za-z]*$")) | index(true)) as $i
         | if $i == null or $depth > 3 then [] else ($a[$i + 1:] | map(clean) | targets($depth + 1)) end)
      elif $h == "tee" then ($a | nonflags | tgt(false))
      elif $h == "sed" then (if any($a[]; test("^-[A-Za-z]*i") or test("^--in-place")) then ($a | nonflags | tgt(false)) else [] end)
      elif $h == "perl" then (if any($a[]; test("^-[A-Za-z]*i")) then ($a | nonflags | tgt(false)) else [] end)
      elif ($h | test("^(rm|rmdir|unlink|chmod|chown|chgrp|mv)$")) then ($a | nonflags | tgt(true))
      elif ($h | test("^(truncate|touch|shred)$")) then ($a | nonflags | tgt(false))
      elif ($h | test("^(cp|ln|install|rsync)$")) then
        (if $h == "ln" and (any($a[]; test("^-[A-Za-z]*s") or . == "--symbolic") | not) then ($a | nonflags | tgt(false))
         elif $h != "rsync" and any($a[]; test("^-[A-Za-z]*t$") or test("^--target-directory") or test("^-t.")) then ($a | nonflags | tgt(true))
         else ($a | nonflags) as $n | if ($n | length) > 0 then [{w: $n[-1], d: true}] else [] end end)
      elif $h == "tar" then ($a | optdir("-C"; "--directory") | tgt(true))
      elif $h == "unzip" then ($a | optdir("-d"; "") | tgt(true))
      elif $h == "patch" then ($a | optdir("-d"; "--directory") | tgt(true))
      elif $h == "dd" then ($a | map(select(startswith("of=")) | .[3:]) | tgt(false))
      elif $h == "git" then
        ($a | gitrest) as $g
        | ($a | index("-C")) as $ci
        | (if ($g | length) > 0 and ($g[0] | test("^(checkout|switch|reset|apply|am|stash|pull|merge|rebase|cherry-pick|restore)$")) then [{w: (if $ci == null then "." else ($a[$ci + 1] // ".") end), live: true}] else [] end)
          + (if ($g | length) == 0 then []
             elif ($g[0] | test("^(restore|rm|mv)$")) then ($g[1:] | nonflags | tgt(true))
             elif $g[0] == "checkout" and ($g | index("--")) != null then ($g[($g | index("--")) + 1:] | tgt(false))
             else [] end)
      elif $h == "find" then
        (($a | map(test("^[-(!]")) | index(true)) as $f
         | ($a | map(test("^-(delete|exec|execdir|ok|okdir)$")) | index(true)) as $e
         | if $e == null then []
           else ($a | if $f == null then . else .[:$f] end | tgt(true))
                + (if $depth > 3 or ($a[$e] == "-delete") then [] else ($a[$e + 1:] | targets($depth + 1)) end)
           end)
      else [] end
    end;
def within($dir; $p): $p | startswith($dir + "/");
def grx: gsub("\\."; "\\.") | gsub("\\*"; "[^/]*") | gsub("\\?"; "[^/]");
def globhit($p; $P; $d):
  ($p | split("/")) as $ps | ($P | split("/")) as $qs
  | if ($ps | length) >= ($qs | length) then ($P | test("^" + ($ps[:($qs | length)] | join("/") | grx) + "$"))
    elif $d then (($qs[:($ps | length)] | join("/")) | test("^" + ($p | grx) + "$"))
    else false end;
def isprot($F; $D; $d):
  ascii_downcase as $p
  | if ($p | test("[*?\\[]")) then any(($F + $D)[]; globhit($p; .; $d))
    else
      any($F[]; . == $p) or any($D[]; . == $p or within(.; $p))
      or ($p | test("/\\.claude/settings(\\.local)?\\.json$"; "i"))
      or ($d and ($p == "/" or any(($F + $D)[]; startswith($p + "/"))))
    end;
def writeverbs: "^(tee|sed|perl|rm|rmdir|unlink|chmod|chown|chgrp|truncate|touch|shred|dd|cp|mv|ln|install|rsync|find)$";
($files | ascii_downcase | lines) as $F
| ($dirs | ascii_downcase | lines) as $D
| ($mains | ascii_downcase | lines | map(norm)) as $M
| if $mode == "file" then
    ($cands | ascii_downcase | lines | map(norm)) as $C
    | first($C[] | select(isprot($F; $D; $isdir)) | "write to protected path " + .) // ""
  else
    (.tool_input.command | if type != "string" or length == 0 then error("no command") else . end) as $cmd
    | [$cmd | segs[]] as $S
    | ([ $S[] as $s | ($s | toks) as $t
         | (($t | redirs) + ($t | targets(0)))[]
         | select(.w | clean | length > 0)
         | . as $x
         | ($x.w | resolve($home; $cwd) | if . == null then . else ascii_downcase end) as $r
         | if $x.live then
             (if $r == null then "git command with unresolvable directory"
              elif any($M[]; . as $m | ($r == $m or ($r | startswith($m + "/"))) and (($r + "/") | startswith($m + "/.worktrees/") | not)) then "git command rewrites the live checkout"
              else empty end)
           elif $r == null then (if ($x.w | test($markers; "i")) then "unresolvable path " + $x.w else empty end)
           elif ($r | isprot($F; $D; $x.d)) then "write to protected path " + $x.w
           else empty end ]
       + [ $S[] as $s
           | select((([$s | match(q; "g")] | length) % 2 == 1) or (([$s | match("\""; "g")] | length) % 2 == 1))
           | select($s | test($markers; "i"))
           | select(($s | test(">")) or any(($s | toks)[]; clean | base | test(writeverbs)))
           | "unparseable command mentions a protected path" ])
    | first // ""
  end
'
if [ "$tool" = Bash ]; then
  reason=$(printf '%s' "$input" | jq -r --arg mode bash --argjson isdir false --arg cands '' --arg home "$home" --arg cwd "$cwd" --arg files "$files" --arg dirs "$dirs" --arg markers "$markers" --arg mains "$mains" "$prog") || block 'cannot analyze command'
else
  p=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty') || block 'cannot parse hook input'
  isdir=false
  if [ -z "$p" ]; then
    p=$(printf '%s' "$input" | jq -r '.tool_input.target_dir // .tool_input.path // empty') || block 'cannot parse hook input'
    isdir=true
  fi
  if [ -z "$p" ]; then
    case $tool in
      mcp__*) exit 0 ;;
    esac
    block 'no file path in tool input'
  fi
  case $p in
    /*) ;;
    *) [ -n "$cwd" ] || block 'relative path without cwd'; p=$cwd/$p ;;
  esac
  cands="$p
"
  q=$p
  n=0
  while [ "$n" -lt 8 ]; do
    d=${q%/*}
    b=${q##*/}
    if [ -d "${d:-/}" ]; then
      pd=$(cd "${d:-/}" && pwd -P) && cands="$cands${pd%/}/$b
"
    fi
    [ -L "$q" ] || break
    t=$(readlink "$q") || break
    case $t in /*) q=$t ;; *) q=${q%/*}/$t ;; esac
    cands="$cands$q
"
    n=$((n + 1))
  done
  reason=$(printf '%s' "$input" | jq -r --arg mode file --argjson isdir "$isdir" --arg cands "$cands" --arg home "$home" --arg cwd "$cwd" --arg files "$files" --arg dirs "$dirs" --arg markers "$markers" --arg mains "$mains" "$prog") || block 'cannot analyze path'
fi
[ -z "$reason" ] || block "$reason"
exit 0
