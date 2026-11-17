#!/usr/bin/env bash
# field-numbers.sh - field numbers of a .proto file across every copy that could own a number, so a
# new field never collides with experimental-bevy / protocol-squad / an open PR / an engine copy.
#
# Usage: field-numbers.sh <proto path under proto/ | MessageName> [--message <name>] [--no-gh]
#                         [--no-engines] [--compact] [--jobs <n>]
#   <arg> is e.g. decentraland/sdk/components/avatar_shape.proto (a leading proto/ is accepted) or
#   a message/service name such as PBAvatarShape or TriggerEmoteRequest (resolved with git grep on
#   origin/main). A message name restricts the report to that message (and its nested ones);
#   --message <name> does the same for a path argument.
#
# Sources: origin/main, origin/experimental-bevy, origin/protocol-squad, origin/experimental (printed
# in full); every other origin/* branch whose copy differs from main (union only, listed once);
# every open PR touching the file (`gh pr diff`, diffs cached once per run in a mktemp dir; the full
# file is read from origin/<headRefName> when that branch is fetched, else rebuilt from the diff's
# context+added lines); the bevy vendored copy crates/dcl_component/src/proto/<path> (origin/main of
# bevy-explorer); the godot extracted copy lib/src/dcl/components/proto/<path> (working tree,
# gitignored); the unity (scripts/package.json) and sdk (package.json) pins
# `1.0.0-<runId>.commit-<sha7>` read with `git show <sha7>:proto/<path>` in the protocol repo.
#
# Per source and per message: field numbers and names (oneof members tagged `(oneof_name)`, nested
# messages as Outer.Inner, enums listed separately, reserved ranges shown). Then the union per
# message, the numbers used off-main that main skips with their owners
# (`13 force_render experimental-bevy,protocol-squad,...`), CONFLICT lines when one number has
# different names across the primary sources, and `NEXT_SAFE_FIELD=<n> <message>` = the smallest
# integer greater than every number seen anywhere, reserved ranges included.
#
# Finally lints the working-tree diff of the file (git diff HEAD -- proto/<path>) and WARNs on:
# a new scalar field without `optional` in a scene-written component (sdk/components, not common/),
# an enum whose first value is not 0, and any comment line containing both `option` and
# `ecs_component_id` (js-sdk-toolchain and godot line parsers would throw).
# WARNINGs also for: gh unavailable/unauthenticated, FETCH_HEAD older than 24h, MISSING repos,
# pin commits not present locally. Read-only; never fetches. Exit 2 on usage errors.
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
usage() { awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; }

ARG=""; MSG=""; NO_GH=0; NO_ENGINES=0; COMPACT=0; JOBS=6
while [ $# -gt 0 ]; do
  case "$1" in
    --message) shift; MSG=${1:-} ;;
    --no-gh) NO_GH=1 ;;
    --no-engines) NO_ENGINES=1 ;;
    --compact) COMPACT=1 ;;
    --jobs) shift; JOBS=${1:-6} ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) ARG=$1 ;;
  esac
  shift
done
[ -n "$ARG" ] || { usage >&2; exit 2; }

PROTOCOL=$("$SCRIPT_DIR/find-repos.sh" --path protocol) || { echo "ERROR: protocol repo not found (run from inside the protocol clone)" >&2; exit 2; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/field-numbers.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT
ROWS="$TMP/rows.tsv"     # source <TAB> kind <TAB> scope <TAB> name <TAB> number <TAB> extra <TAB> type <TAB> order
LABELS="$TMP/labels.tsv" # short label <TAB> description <TAB> primary|aux
: > "$ROWS"; : > "$LABELS"

fetch_age_hours() {
  local gp f m
  gp=$(git -C "$1" rev-parse --git-path FETCH_HEAD 2>/dev/null) || { echo never; return; }
  case "$gp" in /*) f=$gp ;; *) f="$1/$gp" ;; esac
  [ -f "$f" ] || { echo never; return; }
  m=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null) || { echo never; return; }
  echo $(( ($(date +%s) - m) / 3600 ))
}
age=$(fetch_age_hours "$PROTOCOL")
if [ "$age" = never ]; then echo "WARNING: protocol clone was never fetched; origin/* branches may be missing"
elif [ "$age" -gt 24 ]; then echo "WARNING: protocol FETCH_HEAD is ${age}h old; origin/* branches may be stale (git -C $PROTOCOL fetch origin --prune)"; fi

# --- resolve the file
REL=""
case "$ARG" in
  *.proto)
    REL=${ARG#proto/}
    git -C "$PROTOCOL" cat-file -e "origin/main:proto/$REL" 2>/dev/null || echo "WARNING: proto/$REL does not exist on origin/main (new file?)"
    ;;
  *)
    hits=$(git -C "$PROTOCOL" grep -l -E "^[[:space:]]*(message|service|enum)[[:space:]]+$ARG[[:space:]]*\{?" origin/main -- proto 2>/dev/null | sed 's/^origin\/main:proto\///')
    if [ -z "$hits" ]; then
      hits=$(git -C "$PROTOCOL" grep -l -E "^[[:space:]]*(message|service|enum)[[:space:]]+PB$ARG[[:space:]]*\{?" origin/main -- proto 2>/dev/null | sed 's/^origin\/main:proto\///')
      [ -n "$hits" ] && ARG="PB$ARG"
    fi
    [ -n "$hits" ] || { echo "ERROR: no message/service/enum named $ARG on origin/main (git grep in proto/)" >&2; exit 2; }
    REL=$(printf '%s\n' "$hits" | head -1)
    if [ "$(printf '%s\n' "$hits" | wc -l | tr -d ' ')" -gt 1 ]; then
      echo "WARNING: $ARG is declared in more than one file; using the first:"; printf '%s\n' "$hits" | sed 's/^/  /'
    fi
    [ -n "$MSG" ] || MSG=$ARG
    ;;
esac
echo "file: proto/$REL${MSG:+  (message filter: $MSG)}"

# --- proto parser (awk): rows = kind \t scope \t name \t number \t extra \t type \t order
PARSER='
function trim(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }
function push(n, t) { depth++; sname[depth]=n; stype[depth]=t }
function pop() { if (depth>0) { delete sname[depth]; delete stype[depth]; depth-- } }
function msgpath(   i, p) { p=""; for (i=1;i<=depth;i++) if (stype[i]=="message"||stype[i]=="extend"||stype[i]=="enum"||stype[i]=="service") p=(p==""?sname[i]:p "." sname[i]); return p }
function curoneof(   i) { for (i=depth;i>=1;i--) { if (stype[i]=="oneof") return sname[i]; if (stype[i]!="block") return "" } return "" }
function curtype(   i) { for (i=depth;i>=1;i--) if (stype[i]!="oneof" && stype[i]!="block") return stype[i]; return "" }
BEGIN { depth=0; inblk=0; ord=0 }
/^@@HUNK / { depth=0; h=$0; sub(/^@@HUNK[ \t]*/, "", h); if (match(h, /(message|enum|service)[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) { split(substr(h,RSTART,RLENGTH), hp, /[ \t]+/); push(hp[2], hp[1]) } next }
{
  line=$0
  if (inblk) { i=index(line,"*/"); if (i==0) next; line=substr(line,i+2); inblk=0 }
  while ((s=index(line,"/*"))>0) { rest=substr(line,s+2); e=index(rest,"*/"); if (e==0) { line=substr(line,1,s-1); inblk=1; break } line=substr(line,1,s-1) substr(rest,e+2) }
  sub(/\/\/.*$/, "", line)
  gsub(/\[[^\]]*\]/, "", line)
  line=trim(line)
  if (line=="") next
  if (line ~ /^(syntax|package|import)[ \t]/) next
  opens=gsub(/\{/,"{",line); closes=gsub(/\}/,"}",line)
  decl=0
  if (match(line, /^(message|enum|service|oneof|extend)[ \t]+[A-Za-z_][A-Za-z0-9_.]*/)) {
    split(substr(line,RSTART,RLENGTH), parts, /[ \t]+/)
    if (opens>0) { push(parts[2], parts[1]); decl=1 }
  } else if (line ~ /^rpc[ \t]+/) {
    match(line, /^rpc[ \t]+[A-Za-z_][A-Za-z0-9_]*/); split(substr(line,RSTART,RLENGTH), parts, /[ \t]+/)
    print "rpc\t" msgpath() "\t" parts[2] "\t-\t\t\t" (++ord)
  } else if (line ~ /^reserved[ \t]+/) {
    r=line; sub(/^reserved[ \t]+/, "", r); sub(/;.*$/, "", r); nn=split(r, items, /,/)
    for (k=1;k<=nn;k++) { it=trim(items[k])
      if (it ~ /^"/) print "reserved-name\t" msgpath() "\t" it "\t-\t\t\t" (++ord)
      else if (it ~ /^[0-9]+[ \t]+to[ \t]+([0-9]+|max)$/) { split(it, ab, /[ \t]+to[ \t]+/); print "reserved\t" msgpath() "\t" ab[1] "-" ab[2] "\t" ab[1] "\t" ab[2] "\t\t" (++ord) }
      else if (it ~ /^[0-9]+$/) print "reserved\t" msgpath() "\t" it "\t" it "\t" it "\t\t" (++ord) }
  } else if (line ~ /^option[ \t]/) {
  } else if (curtype()=="enum" && match(line, /^[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*-?[0-9]+/)) {
    s=substr(line,RSTART,RLENGTH); split(s, kv, /[ \t]*=[ \t]*/); print "enum-value\t" msgpath() "\t" kv[1] "\t" kv[2] "\t\t\t" (++ord)
  } else if ((curtype()=="message"||curtype()=="extend") && match(line, /=[ \t]*[0-9]+[ \t]*;?$/)) {
    num=substr(line,RSTART,RLENGTH); gsub(/[^0-9]/,"",num)
    lhs=trim(substr(line,1,RSTART-1)); nt=split(lhs, toks, /[ \t]+/); name=toks[nt]
    mod=""; typ=toks[1]
    if (toks[1]=="optional"||toks[1]=="repeated"||toks[1]=="required") { mod=toks[1]; typ=toks[2] }
    o=curoneof()
    print (o=="" ? "field" : "oneof-field") "\t" msgpath() "\t" name "\t" num "\t" (o=="" ? mod : "oneof:" o) "\t" typ "\t" (++ord)
  }
  net = opens - closes - decl
  while (net > 0) { push("", "block"); net-- }
  while (net < 0) { pop(); net++ }
}'

add_source() { # <short label> <file> <description> [aux]
  awk "$PARSER" "$2" | awk -F'\t' -v src="$1" 'BEGIN{OFS="\t"} { print src, $1, $2, $3, $4, $5, $6, $7 }' >> "$ROWS"
  printf '%s\t%s\t%s\n' "$1" "$3" "${4:-primary}" >> "$LABELS"
}

# --- protocol branches
MAIN_FILE="$TMP/main.proto"
git -C "$PROTOCOL" show "origin/main:proto/$REL" > "$MAIN_FILE" 2>/dev/null || : > "$MAIN_FILE"
for b in main experimental-bevy protocol-squad experimental; do
  f="$TMP/branch-$b.proto"
  if git -C "$PROTOCOL" show "origin/$b:proto/$REL" > "$f" 2>/dev/null; then add_source "origin/$b" "$f" "protocol branch"
  else echo "note: origin/$b has no proto/$REL (branch missing locally or file absent)"; fi
done
others=""
for ref in $(git -C "$PROTOCOL" for-each-ref --format='%(refname:short)' refs/remotes/origin | grep -v -E '^origin/(HEAD|main|experimental-bevy|protocol-squad|experimental)$'); do
  f="$TMP/aux-$(printf '%s' "${ref#origin/}" | tr '/' '_').proto"
  git -C "$PROTOCOL" show "$ref:proto/$REL" > "$f" 2>/dev/null || continue
  cmp -s "$f" "$MAIN_FILE" && continue
  add_source "${ref#origin/}" "$f" "other branch" aux; others="$others ${ref#origin/}"
done
[ -n "$others" ] && echo "other origin/* branches whose copy differs from main (union only):$others"

# --- open PRs touching the file
if [ "$NO_GH" = 1 ]; then echo "WARNING: --no-gh: open PRs not scanned; numbers claimed by open PRs are invisible"
elif ! command -v gh >/dev/null 2>&1; then echo "WARNING: gh unavailable: open PRs not scanned; numbers claimed by open PRs are invisible"
elif ! gh auth status >/dev/null 2>&1; then echo "WARNING: gh is not authenticated (gh auth login): open PRs not scanned"
elif gh pr list --repo decentraland/protocol --state open --limit 100 --json number,headRefName,title --jq '.[] | "\(.number)\t\(.headRefName)\t\(.title)"' > "$TMP/prs.tsv" 2>"$TMP/gh.err"; then
  cut -f1 "$TMP/prs.tsv" | xargs -P "$JOBS" -I{} sh -c '
    gh pr diff "$1" --repo decentraland/protocol --name-only > "$0/pr-$1.names" 2>/dev/null || { echo "WARNING: gh pr diff $1 --name-only failed; PR #$1 not scanned"; exit 0; }
    grep -q -x -F "proto/$2" "$0/pr-$1.names" || exit 0
    gh pr diff "$1" --repo decentraland/protocol > "$0/pr-$1.diff" 2>/dev/null || echo "WARNING: gh pr diff $1 failed; PR #$1 not scanned"' "$TMP" {} "$REL"
  npr=0
  while IFS='	' read -r num head title; do
    [ -n "$num" ] || continue; npr=$((npr+1))
    [ -s "$TMP/pr-$num.diff" ] || continue
    f="$TMP/pr-$num.proto"
    if git -C "$PROTOCOL" show "origin/$head:proto/$REL" > "$f" 2>/dev/null; then
      add_source "#$num" "$f" "open PR: $title; full file from fetched origin/$head"
    else
      awk -v want="proto/$REL" '
        /^diff --git / { infile = ($0 ~ (" b/" want "$")) ; next }
        !infile { next }
        /^(---|\+\+\+|index |new file|deleted file|similarity|rename) / { next }
        /^@@/ { h=$0; sub(/^@@[^@]*@@[ \t]*/, "", h); print "@@HUNK " h; next }
        /^-/ { next }
        { print substr($0, 2) }' "$TMP/pr-$num.diff" > "$f"
      add_source "#$num" "$f" "open PR: $title; head $head not fetched, rebuilt from the diff (context + added lines only)"
    fi
  done < "$TMP/prs.tsv"
  echo "scanned $npr open PRs"
else
  echo "WARNING: gh pr list failed ($(head -1 "$TMP/gh.err" 2>/dev/null)); open PRs not scanned"
fi

# --- engine copies and pins
if [ "$NO_ENGINES" = 0 ]; then
  BEVY=$("$SCRIPT_DIR/find-repos.sh" --path bevy-explorer) || BEVY=""
  if [ -n "$BEVY" ]; then
    f="$TMP/bevy.proto"
    if git -C "$BEVY" show "origin/main:crates/dcl_component/src/proto/$REL" > "$f" 2>/dev/null; then add_source "bevy" "$f" "vendored crates/dcl_component/src/proto/$REL on bevy origin/main"
    elif [ -f "$BEVY/crates/dcl_component/src/proto/$REL" ]; then cp "$BEVY/crates/dcl_component/src/proto/$REL" "$f"; add_source "bevy" "$f" "vendored copy, bevy working tree (not on origin/main)"
    else echo "note: bevy has no vendored copy of $REL"; fi
  else echo "WARNING: bevy-explorer MISSING: vendored copy not scanned (gh repo clone decentraland/bevy-explorer)"; fi

  GODOT=$("$SCRIPT_DIR/find-repos.sh" --path godot-explorer) || GODOT=""
  if [ -n "$GODOT" ]; then
    if [ -f "$GODOT/lib/src/dcl/components/proto/$REL" ]; then cp "$GODOT/lib/src/dcl/components/proto/$REL" "$TMP/godot.proto"; add_source "godot" "$TMP/godot.proto" "extracted lib/src/dcl/components/proto/$REL (working tree, from the last cargo run -- install)"
    elif [ -d "$GODOT/lib/src/dcl/components/proto" ]; then echo "note: godot extracted protos lack $REL (pin predates it?)"
    else echo "WARNING: godot-explorer found but protos are not extracted (cargo run -- install); godot copy not scanned"; fi
  else echo "WARNING: godot-explorer MISSING: extracted copy not scanned (gh repo clone decentraland/godot-explorer)"; fi

  pin_source() { # <label> <repo-dir> <ref> <package.json path>
    local v sha
    v=$( { git -C "$2" show "$3:$4" 2>/dev/null || cat "$2/$4" 2>/dev/null; } | grep -o '"@dcl/protocol": *"[^"]*"' | head -1 | sed 's/.*: *"//; s/"$//')
    [ -n "$v" ] || { echo "note: $1: no @dcl/protocol pin in $4"; return; }
    sha=$(printf '%s' "$v" | sed -n 's/.*commit-\([0-9a-f]\{7,\}\).*/\1/p')
    [ -n "$sha" ] || { echo "note: $1 pin '$v' has no commit-<sha7>; cannot resolve"; return; }
    if ! git -C "$PROTOCOL" cat-file -e "$sha^{commit}" 2>/dev/null; then echo "WARNING: $1 pin commit $sha is not in the local protocol clone (fetch); pin copy not scanned"; return; fi
    if git -C "$PROTOCOL" show "$sha:proto/$REL" > "$TMP/pin-$1.proto" 2>/dev/null; then add_source "$1-pin" "$TMP/pin-$1.proto" "$4 on $3 pins $v -> protocol commit $sha"
    else echo "note: $1 pin $sha predates proto/$REL"; fi
  }
  UNITY=$("$SCRIPT_DIR/find-repos.sh" --path unity-explorer) || UNITY=""
  if [ -n "$UNITY" ]; then pin_source unity "$UNITY" origin/dev scripts/package.json
  else echo "WARNING: unity-explorer MISSING: pin not resolved (gh repo clone decentraland/unity-explorer)"; fi
  SDK=$("$SCRIPT_DIR/find-repos.sh" --path js-sdk-toolchain) || SDK=""
  if [ -n "$SDK" ]; then pin_source sdk "$SDK" origin/main package.json
  else echo "WARNING: js-sdk-toolchain MISSING: pin not resolved (gh repo clone decentraland/js-sdk-toolchain)"; fi
fi

[ -s "$ROWS" ] || { echo "ERROR: nothing parsed for proto/$REL" >&2; exit 2; }

# --- message filter: the message, PB<message>, and anything nested under it
if [ -n "$MSG" ]; then
  awk -F'\t' -v m="$MSG" 'BEGIN{OFS="\t"} { s=$3; if (s==m || s=="PB" m || index(s, m ".")==1 || index(s, "PB" m ".")==1 || s ~ ("\\." m "$") || s ~ ("\\." m "\\.")) print }' "$ROWS" > "$TMP/rows.f" && mv "$TMP/rows.f" "$ROWS"
  [ -s "$ROWS" ] || { echo "ERROR: message $MSG not found in any copy of proto/$REL" >&2; exit 2; }
fi
# order: origin/main first (its names are canonical in the union), then the other sources; fields by number inside each scope
{ awk -F"\t" "\$1==\"origin/main\"" "$ROWS" | sort -t"	" -k3,3 -k5,5n; awk -F"\t" "\$1!=\"origin/main\"" "$ROWS" | sort -t"	" -k1,1 -k3,3 -k5,5n; } > "$TMP/rows.sorted" && cp "$TMP/rows.sorted" "$ROWS"

print_source() { # <label>
  awk -F'\t' -v src="$1" '
    $1!=src { next }
    { scope=$3; if (!(scope in seen)) { seen[scope]=1; order[++n]=scope } k=$2
      if (k=="field" || k=="oneof-field") { v=$5 " " $4; if (k=="oneof-field") { o=$6; sub(/^oneof:/, "", o); v = v "(" o ")" } fields[scope] = fields[scope] (fields[scope]==""?"":", ") v }
      else if (k=="enum-value") { enums[scope] = enums[scope] (enums[scope]==""?"":", ") $5 " " $4; isenum[scope]=1 }
      else if (k=="reserved") { res[scope] = res[scope] (res[scope]==""?"":", ") $4 }
      else if (k=="rpc") { rpcs[scope] = rpcs[scope] (rpcs[scope]==""?"":", ") $4 } }
    END { for (i=1;i<=n;i++) { s=order[i]
      if (s in isenum) printf "  enum %s: %s\n", s, enums[s]
      else if (s in rpcs) printf "  service %s: rpc %s\n", s, rpcs[s]
      else { line = fields[s]; if (s in res) line = line (line==""?"":"; ") "reserved " res[s]; printf "  %s: %s\n", s, (line==""?"(no fields)":line) } } }' "$ROWS"
}
signature() { awk -F'\t' -v s="$1" '$1==s && ($2=="field"||$2=="oneof-field"||$2=="enum-value"||$2=="reserved") { print $2 "\t" $3 "\t" $4 "\t" $5 }' "$ROWS" | sort; }
main_sig=$(signature origin/main)

echo
awk -F'\t' '$3=="primary" { print $1 "\t" $2 }' "$LABELS" | while IFS='	' read -r src desc; do
  if [ "$COMPACT" = 1 ] && [ "$src" != origin/main ] && [ "$(signature "$src")" = "$main_sig" ]; then echo "== $src ($desc): identical numbering to origin/main"; continue; fi
  echo "== $src ($desc)"; print_source "$src"
done

# --- union, conflicts, off-main, next safe
AUXLIST="|$(awk -F'\t' '$3=="aux" { printf "%s|", $1 }' "$LABELS")"
echo
echo "== union (all sources; owners ordered: protocol branches, open PRs, engine copies, pins, other branches)"
awk -F'\t' -v auxlist="$AUXLIST" '
  function rk(s) { if (index(auxlist, "|" s "|")) return 4; if (s ~ /^origin\//) return 0; if (s ~ /^#/) return 1; if (s=="bevy"||s=="godot") return 2; return 3 }
  function sorted(list,   a, m, x, y, v, out) { m=split(list, a, ","); for (x=2;x<=m;x++) { v=a[x]; y=x-1; while (y>=1 && (rk(a[y]) > rk(v) || (rk(a[y])==rk(v) && a[y] > v))) { a[y+1]=a[y]; y-- } a[y+1]=v }
    out=""; for (x=1;x<=m;x++) out = out (out==""?"":",") a[x]; return out }
  ($2=="field"||$2=="oneof-field") { k=$3 SUBSEP $5; isaux = index(auxlist, "|" $1 "|") > 0
    if (!(k in name)) { name[k]=$4; if (!($3 in seen)) { seen[$3]=1; order[++n]=$3 } nums[$3] = nums[$3] " " $5 }
    else if (name[k] != $4 && !isaux && index("|" alt[k] "|", "|" $4 "|")==0) alt[k] = alt[k] (alt[k]==""?"":"|") $4 "(" $1 ")"
    if (!((k SUBSEP $4 SUBSEP $1) in ss)) { ss[k SUBSEP $4 SUBSEP $1]=1; src[k SUBSEP $4] = src[k SUBSEP $4] (src[k SUBSEP $4]==""?"":",") $1 }
    if ($1=="origin/main") onmain[k]=1
    if ($5+0 > mx[$3]) mx[$3]=$5+0 }
  $2=="reserved" { if (!($3 in seen)) { seen[$3]=1; order[++n]=$3 } if ($6+0 > mx[$3]) mx[$3]=$6+0; if ($5+0 > mx[$3]) mx[$3]=$5+0; if (!(($3 SUBSEP $4) in rs)) { rs[$3 SUBSEP $4]=1; res[$3] = res[$3] (res[$3]==""?"":", ") $4 } }
  $2=="enum-value" { ek=$3 SUBSEP $5; if (!(ek in ename)) { ename[ek]=$4; enums[$3] = enums[$3] (enums[$3]==""?"":", ") $5 " " $4; if (!($3 in seen)) { seen[$3]=1; order[++n]=$3 } } else if (ename[ek]!=$4 && index(auxlist, "|" $1 "|")==0) econf[$3] = econf[$3] " " $5 "=" ename[ek] "|" $4 "(" $1 ")" }
  END {
    for (i=1;i<=n;i++) { s=order[i]
      if (s in enums) { printf "  enum %s: %s\n", s, enums[s]; if (s in econf) printf "  CONFLICT enum %s:%s\n", s, econf[s]; continue }
      m=split(nums[s], a, " "); for (x=2;x<=m;x++) { v=a[x]+0; y=x-1; while (y>=1 && a[y]+0 > v) { a[y+1]=a[y]; y-- } a[y+1]=v }
      line=""; off=""; conf=""
      for (x=1;x<=m;x++) { if (a[x]=="") continue; k=s SUBSEP a[x]; line = line (line==""?"":", ") a[x] " " name[k]
        if (!(k in onmain)) off = off "\n    " a[x] " " name[k] " " sorted(src[k SUBSEP name[k]])
        if (alt[k]!="") conf = conf "\n    CONFLICT " s " " a[x] ": " name[k] " (" sorted(src[k SUBSEP name[k]]) ") vs " alt[k] }
      if (s in res) line = line (line==""?"":"; ") "reserved " res[s]
      printf "  %s: %s\n", s, (line==""?"(no fields)":line)
      if (off!="") printf "  off-main (absent on origin/main; owner list):%s\n", off
      if (conf!="") printf "%s\n", substr(conf, 2)
      printf "  NEXT_SAFE_FIELD=%d %s\n", mx[s]+1, s } }' "$ROWS"

# --- lint the working-tree diff of this file
echo
is_scene=0
case "$REL" in decentraland/sdk/components/common/*) ;; decentraland/sdk/components/*) is_scene=1 ;; esac
WT="$PROTOCOL/proto/$REL"
diff=$(git -C "$PROTOCOL" diff HEAD -- "proto/$REL" 2>/dev/null)
if [ -z "$diff" ] && git -C "$PROTOCOL" ls-files --error-unmatch "proto/$REL" >/dev/null 2>&1; then
  echo "lint: no working-tree changes in proto/$REL"
elif [ -z "$diff" ] && [ ! -f "$WT" ]; then
  echo "lint: proto/$REL is not in the working tree"
else
  echo "lint: working-tree diff of proto/$REL"
  if [ -n "$diff" ]; then printf '%s\n' "$diff" | grep -E '^\+[^+]' | sed 's/^+//' > "$TMP/added"; else cat "$WT" > "$TMP/added"; echo "  (untracked file: linting every line)"; fi
  nwarn=0
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    code=${l%%//*}
    if [ "$code" != "$l" ]; then c=${l#*//}; case "$c" in *option*ecs_component_id*|*ecs_component_id*option*) echo "  WARNING: comment line contains both 'option' and 'ecs_component_id' (sdk/godot id parsers throw): $l"; nwarn=$((nwarn+1));; esac; fi
    if [ "$is_scene" = 1 ] && printf '%s' "$code" | grep -q -E '^[[:space:]]*(double|float|int32|int64|uint32|uint64|sint32|sint64|fixed32|fixed64|sfixed32|sfixed64|bool|string|bytes)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*[0-9]+'; then
      echo "  WARNING: new scalar field without 'optional' in a scene-written component (becomes a required TS property; fine only inside a oneof): $(printf '%s' "$code" | sed 's/^[[:space:]]*//')"; nwarn=$((nwarn+1))
    fi
  done < "$TMP/added"
  if [ -f "$WT" ]; then
    awk "$PARSER" "$WT" | awk -F'\t' '$1=="enum-value" && !($2 in first) { first[$2]=$4; if ($4+0 != 0) print "  WARNING: enum " $2 " first value is " $3 " = " $4 " (must be 0; buf ENUM_FIRST_VALUE_ZERO)" }' > "$TMP/enumwarn"
    cat "$TMP/enumwarn"; nwarn=$((nwarn + $(grep -c . "$TMP/enumwarn")))
    if [ "$is_scene" = 1 ]; then
      n=$(grep -c -E 'option.*ecs_component_id|ecs_component_id.*option' "$WT")
      [ "$n" = 1 ] || { echo "  WARNING: $n lines contain both 'option' and 'ecs_component_id' in proto/$REL (exactly one is required by the sdk/godot id parsers)"; nwarn=$((nwarn+1)); }
    fi
  fi
  [ "$nwarn" = 0 ] && echo "  no lint warnings"
fi
exit 0
