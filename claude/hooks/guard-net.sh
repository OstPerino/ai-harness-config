#!/bin/sh
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
input=$(cat)
block() {
  printf 'guard-net: %s\n' "$1" >&2
  exit 2
}
command -v jq >/dev/null 2>&1 || block 'jq not found, refusing to run'
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty') || block 'cannot parse hook input'
[ -n "$tool" ] || block 'empty tool_name'
[ "$tool" = Bash ] || exit 0
prog='
def clean: gsub("[" + ([39] | implode) + "\"\\\\]"; "");
def toks: [splits("[ \t]+")] | map(select(length > 0));
def base: sub("^.*/"; "") | ascii_downcase;
def groups:
  gsub("\\|\\||&&|\\$\\(|[`()]"; "\u0001") | gsub("\\|&"; "\u0002") | gsub("\\|"; "\u0002") | gsub("[;&\n]"; "\u0001")
  | split("\u0001") | map(split("\u0002"));
def lead($w):
  if length == 0 then .
  elif (.[0] | clean | base | test("^(sudo|doas|env|command|exec|nohup|time|nice|xargs|stdbuf|timeout|builtin)$")) then .[1:] | lead(true)
  elif (.[0] | test("^[A-Za-z_][A-Za-z0-9_]*=")) then .[1:] | lead($w)
  elif $w and (.[0] | test("^-[ugpCDRTUILP]$")) then .[2:] | lead($w)
  elif $w and (.[0] | test("^-[nks]$")) and ((.[1] // "") | test("^[0-9.]+[smhd]?$")) then .[2:] | lead($w)
  elif $w and (.[0] | test("^-")) then .[1:] | lead($w)
  elif $w and (.[0] | test("^[0-9.]+[smhd]?$")) then .[1:] | lead($w)
  else . end;
def curlbad($a):
  any(range(0; $a | length);
    . as $i | $a[$i] as $x | ($a[$i + 1] // "") as $n
    | ($x | test("^(--data(-binary|-ascii)?|--json)=@"))
      or ($x | test("^-[A-Za-z]*d@"))
      or (($x | test("^(-[A-Za-z]*d|--data(-binary|-ascii)?|--json)$")) and ($n | startswith("@")))
      or ($x | test("^--data-urlencode=.*@"))
      or ($x == "--data-urlencode" and ($n | contains("@")))
      or ($x | test("^(-F.*|--form=.*)=[@<]"))
      or (($x == "-F" or $x == "--form") and ($n | test("=[@<]")))
      or ($x | test("^-[A-Za-z]*T"))
      or ($x | test("^--upload-file(=|$)"))
      or ($x | test("^-[A-Za-z]*H@"))
      or (($x == "-H" or $x == "--header") and ($n | startswith("@")))
      or ($x | test("^--header=@"))
      or ($x == "--variable" and ($n | contains("@")))
      or ($x | test("^--variable=.*@"))
      or ($x == "--url-query" and ($n | contains("@")))
      or ($x | test("^--url-query=.*@"))
      or ($x | test("^-[A-Za-z]*K"))
      or ($x | test("^--config(=|$)")));
def raw: gsub("\\|\\||&&|\\||[;&\n]"; "\u0001") | split("\u0001");
def wgetbad($a): any($a[]; test("^--(post-file|body-file)(=|$)"));
def chk($piped; $depth):
  lead(false) as $c
  | if ($c | length) == 0 then null
    else ($c[0] | clean | base) as $h | ($c[1:] | map(clean)) as $a
    | if $piped and ($h | test("^(sh|bash|zsh|dash|ksh|ash)$")) then "pipe into " + $h
      elif ($h | test("^(nc|ncat|netcat|socat)$")) then "raw network tool " + $h
      elif ($h == "curl" and curlbad($a)) then "curl sends file contents"
      elif ($h == "wget" and wgetbad($a)) then "wget sends file contents"
      elif ($h | test("^(sh|bash|zsh|dash|ksh|ash)$")) and $depth < 4 then
        (($a | map(test("^-[A-Za-z]*c$")) | index(true)) as $i
         | if $i == null then null else ($a[$i + 1:] | chk(false; $depth + 1)) end)
      else null end
    end;
(.tool_input.command | if type != "string" or length == 0 then error("no command") else . end) as $cmd
| (if ($cmd | test("<\\(\\s*(curl|wget)\\b"; "i")) then "process substitution runs downloaded code"
   elif ($cmd | test("\\b(sh|bash|zsh|dash|ksh|ash)\\s+(-[A-Za-z]+\\s+)*-[A-Za-z]*c\\b[^;&|\n]*(\\$\\(|`)\\s*(curl|wget)\\b"; "i")) then "shell -c runs downloaded code"
   elif ($cmd | test("\\beval\\b[^;&|\n]*(\\$\\(|`)\\s*(curl|wget)\\b"; "i")) then "eval runs downloaded code"
   elif ($cmd | test("\\b(sh|bash|zsh|dash|ksh|ash)\\b[^;&|\n]*<<<"; "i")) then "here-string into a shell"
   else null end) as $r1
| (first($cmd | raw[] | select(test("\\$\\(|`")) | select(toks | lead(false) | (.[0] // "") | clean | base | test("^(curl|wget)$")) | "curl or wget with command substitution") // null) as $r3
| [$cmd | groups[] | to_entries[] | .key as $i | (.value | toks) | chk($i > 0; 0)] as $r2
| ([$r1, $r3] + $r2 | map(select(. != null)) | first // "")
'
reason=$(printf '%s' "$input" | jq -r "$prog") || block 'cannot analyze command'
[ -z "$reason" ] || block "$reason"
exit 0
