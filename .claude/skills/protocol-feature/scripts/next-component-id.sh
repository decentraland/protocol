#!/usr/bin/env bash
# next-component-id.sh - next free `option (common.ecs_component_id) = N` across EVERY place an id
# can be claimed, not just the local tree (the 1221 collision in #464 happened because only the
# local tree was checked).
#
# Usage: next-component-id.sh [--check <id>] [--min <id>] [--no-gh] [--no-engines] [--jobs <n>]
#
# Sources (union):
#   - every fetched origin/* branch of the protocol repo (git grep on the ref, so working trees
#     do not matter): origin/main, origin/experimental-bevy, origin/protocol-squad,
#     origin/experimental and all the others
#   - every open PR of decentraland/protocol that touches proto/ (`gh pr list` + `gh pr diff`,
#     each diff fetched once per run into a mktemp dir), `+option (common.ecs_component_id) = N`
#   - engine copies when the repo is found (see find-repos.sh): bevy
#     crates/dcl_component/src/lib.rs `SceneComponentId(N)` consts, godot extracted protos under
#     lib/src/dcl/components/proto/ (gitignored, working tree only), unity
#     Explorer/Assets/Protocol/DecentralandProtocol/ComponentID.gen.cs
#
# Prints a table of ids >= --min (default 1200) with their claimants, `NEXT_SAFE_ID=<n>` (the
# first id above main's max that nobody claims anywhere) and a one-line RATIONALE to paste in a
# PR body: `main max 1222; open PRs 1223 (#495), 1224-1225 (#499); off-main 1200-1208, ...`.
# "off-main" = ids absent from main but used by the integration branches (experimental-bevy,
# protocol-squad, experimental), engine copies or feature branches; "open PRs" = ids added by
# ordinary open PRs. Then runs `make check-component-id ID=<n>` labelled "(local tree only)".
# `--check <id>` prints `free` (exit 0) or `taken by <claimants>` (exit 1).
# Prints WARNING lines when gh is unavailable/unauthenticated (open PRs not scanned), when
# FETCH_HEAD is older than 24h, or when an engine repo is MISSING. Read-only; never fetches.
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
usage() { awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; }

CHECK=""; MIN=1200; NO_GH=0; NO_ENGINES=0; JOBS=6
while [ $# -gt 0 ]; do
  case "$1" in
    --check) shift; CHECK=${1:-} ;;
    --min) shift; MIN=${1:-1200} ;;
    --jobs) shift; JOBS=${1:-6} ;;
    --no-gh) NO_GH=1 ;;
    --no-engines) NO_ENGINES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
case "$CHECK" in ''|*[0-9]*) ;; *) echo "ERROR: --check needs a number" >&2; exit 2 ;; esac

PROTOCOL=$("$SCRIPT_DIR/find-repos.sh" --path protocol) || { echo "ERROR: protocol repo not found (run from inside the protocol clone)" >&2; exit 2; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/next-component-id.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT
CLAIMS="$TMP/claims.tsv"   # id <TAB> claimant <TAB> component <TAB> kind(main|integration|branch|pr|ipr|engine)
: > "$CLAIMS"
: > "$TMP/prs.tsv"
INTEGRATION="experimental-bevy protocol-squad experimental protocol-squad-sync-main"

fetch_age_hours() {
  local gp f m
  gp=$(git -C "$1" rev-parse --git-path FETCH_HEAD 2>/dev/null) || { echo never; return; }
  case "$gp" in /*) f=$gp ;; *) f="$1/$gp" ;; esac
  [ -f "$f" ] || { echo never; return; }
  m=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null) || { echo never; return; }
  echo $(( ($(date +%s) - m) / 3600 ))
}
age=$(fetch_age_hours "$PROTOCOL")
if [ "$age" = never ]; then echo "WARNING: protocol clone was never fetched; origin/* branches may be missing (git -C $PROTOCOL fetch origin --prune)"
elif [ "$age" -gt 24 ]; then echo "WARNING: protocol FETCH_HEAD is ${age}h old; origin/* branches may be stale (git -C $PROTOCOL fetch origin --prune)"; fi

is_integration() { case " $INTEGRATION " in *" $1 "*) return 0 ;; esac; return 1; }

echo "protocol: $PROTOCOL (ids read from fetched origin/* refs, open PRs and engine copies)"

# --- 1. every origin/* branch
branches=$(git -C "$PROTOCOL" for-each-ref --format='%(refname:short)' refs/remotes/origin | grep -v '^origin/HEAD$')
nb=0
for ref in $branches; do
  nb=$((nb+1))
  name=${ref#origin/}
  kind=branch
  [ "$name" = main ] && kind=main
  is_integration "$name" && kind=integration
  git -C "$PROTOCOL" grep -o -E 'ecs_component_id\) *= *[0-9]+' "$ref" -- proto 2>/dev/null \
    | awk -F: -v name="$name" -v kind="$kind" '{
        id=$NF; gsub(/[^0-9]/, "", id);
        n=split($2, p, "/"); comp=p[n]; sub(/\.proto$/, "", comp);
        print id "\t" name "\t" comp "\t" kind }' >> "$CLAIMS"
done
echo "scanned $nb origin/* branches"

# --- 2. open PRs touching proto/ (diffs fetched in parallel, once per run)
gh_ok=0
if [ "$NO_GH" = 1 ]; then
  echo "WARNING: --no-gh: open PRs not scanned; ids claimed by open PRs are invisible"
elif ! command -v gh >/dev/null 2>&1; then
  echo "WARNING: gh unavailable: open PRs not scanned; ids claimed by open PRs are invisible"
elif ! gh auth status >/dev/null 2>&1; then
  echo "WARNING: gh is not authenticated (gh auth login): open PRs not scanned"
else
  gh_ok=1
fi
if [ "$gh_ok" = 1 ]; then
  if gh pr list --repo decentraland/protocol --state open --limit 100 \
       --json number,headRefName,title --jq '.[] | "\(.number)\t\(.headRefName)\t\(.title)"' > "$TMP/prs.tsv" 2>"$TMP/gh.err"; then
    cut -f1 "$TMP/prs.tsv" | xargs -P "$JOBS" -I{} sh -c '
      gh pr diff "$1" --repo decentraland/protocol --name-only > "$0/pr-$1.names" 2>/dev/null || { echo "WARNING: gh pr diff $1 --name-only failed; PR #$1 not scanned"; exit 0; }
      grep -q "^proto/" "$0/pr-$1.names" || exit 0
      gh pr diff "$1" --repo decentraland/protocol > "$0/pr-$1.diff" 2>/dev/null || echo "WARNING: gh pr diff $1 failed; PR #$1 not scanned"' "$TMP" {}
    npr=0; nproto=0
    while IFS='	' read -r num head title; do
      [ -n "$num" ] || continue
      npr=$((npr+1))
      [ -s "$TMP/pr-$num.diff" ] || continue
      nproto=$((nproto+1))
      kind=pr; is_integration "$head" && kind=ipr
      awk -v pr="#$num" -v kind="$kind" '
        /^\+\+\+ / { f=$0; sub(/^\+\+\+ b\//, "", f); n=split(f, p, "/"); comp=p[n]; sub(/\.proto$/, "", comp); next }
        /^\+/ && $0 !~ /^\+\+\+/ && $0 ~ /ecs_component_id\) *= *[0-9]+/ {
          id=$0; sub(/.*ecs_component_id\) *= */, "", id); gsub(/[^0-9].*/, "", id);
          print id "\t" pr "\t" comp "\t" kind }' "$TMP/pr-$num.diff" >> "$CLAIMS"
    done < "$TMP/prs.tsv"
    echo "scanned $npr open PRs ($nproto touch proto/)"
  else
    echo "WARNING: gh pr list failed ($(head -1 "$TMP/gh.err" 2>/dev/null)); open PRs not scanned"
  fi
fi

# --- 3. engine copies
if [ "$NO_ENGINES" = 1 ]; then
  echo "note: --no-engines: engine copies not scanned"
else
  BEVY=$("$SCRIPT_DIR/find-repos.sh" --path bevy-explorer) || BEVY=""
  if [ -n "$BEVY" ]; then
    { git -C "$BEVY" show origin/main:crates/dcl_component/src/lib.rs 2>/dev/null; cat "$BEVY/crates/dcl_component/src/lib.rs" 2>/dev/null; } \
      | sed -n -E 's/.*pub const ([A-Z0-9_]+): *SceneComponentId *= *SceneComponentId\(([0-9]+)\).*/\2\tbevy\t\1\tengine/p' \
      | awk -F'\t' '{ print $1 "\t" $2 "\t" tolower($3) "\t" $4 }' | sort -u >> "$CLAIMS"
  else
    echo "WARNING: bevy-explorer MISSING: bevy SceneComponentId consts not scanned (gh repo clone decentraland/bevy-explorer)"
  fi
  GODOT=$("$SCRIPT_DIR/find-repos.sh" --path godot-explorer) || GODOT=""
  if [ -n "$GODOT" ]; then
    gdir="$GODOT/lib/src/dcl/components/proto/decentraland/sdk/components"
    if [ -d "$gdir" ]; then
      grep -o -E 'ecs_component_id\) *= *[0-9]+' "$gdir"/*.proto 2>/dev/null \
        | awk -F: '{ id=$NF; gsub(/[^0-9]/, "", id); n=split($1, p, "/"); comp=p[n]; sub(/\.proto$/, "", comp); print id "\tgodot\t" comp "\tengine" }' >> "$CLAIMS"
    else
      echo "WARNING: godot-explorer found but lib/src/dcl/components/proto is not extracted (cargo run -- install); godot copy not scanned"
    fi
  else
    echo "WARNING: godot-explorer MISSING: godot extracted protos not scanned (gh repo clone decentraland/godot-explorer)"
  fi
  UNITY=$("$SCRIPT_DIR/find-repos.sh" --path unity-explorer) || UNITY=""
  if [ -n "$UNITY" ]; then
    ufile="Explorer/Assets/Protocol/DecentralandProtocol/ComponentID.gen.cs"
    { git -C "$UNITY" show "origin/dev:$ufile" 2>/dev/null; cat "$UNITY/$ufile" 2>/dev/null; } \
      | sed -n -E 's/.*public const int ([A-Z0-9_]+) *= *([0-9]+);.*/\2\tunity\t\1\tengine/p' \
      | awk -F'\t' '{ print $1 "\t" $2 "\t" tolower($3) "\t" $4 }' | sort -u >> "$CLAIMS"
  else
    echo "WARNING: unity-explorer MISSING: ComponentID.gen.cs not scanned (gh repo clone decentraland/unity-explorer)"
  fi
fi

sort -u "$CLAIMS" -o "$CLAIMS"
[ -s "$CLAIMS" ] || { echo "ERROR: no ids found at all (is this the protocol repo?)" >&2; exit 2; }

# --- aggregate per id: table.tsv = id, component, claimants(display), class, pr-owners, mismatch
# class: main | pr (added by an ordinary open PR) | offmain (integration branch / engine / feature branch)
awk -F'\t' '
  function rank(k) { return (k=="main") ? 0 : (k=="integration") ? 1 : (k=="ipr") ? 2 : (k=="pr") ? 3 : (k=="engine") ? 4 : 5 }
  { id=$1; who=$2; comp=$3; kind=$4
    if (!(id in seen)) { seen[id]=1; ids[++n]=id }
    key = id SUBSEP who
    if (!(key in cl)) { cl[key]=1; claims[id] = claims[id] (claims[id]==""?"":"\n") rank(kind) "\t" who "\t" kind }
    if (kind=="main") mainname[id]=comp
    if (kind=="main" || kind=="pr" || kind=="engine") { nk = id SUBSEP comp; if (!(nk in nseen)) { nseen[nk]=1; names[id] = names[id] (names[id]==""?"":"|") comp; nn[id]++ } }
    if (kind=="branch" && !(id in anyname)) anyname[id]=comp
  }
  END {
    for (i=1;i<=n;i++) {
      id=ids[i]; m=split(claims[id], arr, "\n")
      for (a=2;a<=m;a++) { v=arr[a]; b=a-1; while (b>=1 && arr[b] > v) { arr[b+1]=arr[b]; b-- } arr[b+1]=v }
      onmain=0; nbr=0; brs=""; prs=""; prsd=""; iprs=""; integ=""; eng=""; cls=""
      for (a=1;a<=m;a++) { split(arr[a], f, "\t"); who=f[2]; kind=f[3]
        if (kind=="main") onmain=1
        else if (kind=="branch") { nbr++; brs = brs (brs==""?"":", ") who }
        else if (kind=="pr") { prs = prs (prs==""?"":",") who; prsd = prsd (prsd==""?"":", ") who }
        else if (kind=="ipr") iprs = iprs (iprs==""?"":", ") who
        else if (kind=="integration") integ = integ (integ==""?"":", ") who
        else if (kind=="engine") eng = eng (eng==""?"":", ") who }
      if (onmain) { cls="main"; disp="main"
        if (integ!="") disp = disp ", " integ
        if (iprs!="") disp = disp ", " iprs
        if (prs!="") disp = disp ", " prsd
        if (eng!="") disp = disp ", " eng
        if (nbr>0) disp = disp " (+" nbr " feature branches)" }
      else { cls = (integ!="" || iprs!="" || eng!="") ? "offmain" : (prs!="") ? "pr" : "offmain"
        disp=""
        if (integ!="") disp = integ
        if (iprs!="") disp = disp (disp==""?"":", ") iprs
        if (prs!="") disp = disp (disp==""?"":", ") prsd
        if (eng!="") disp = disp (disp==""?"":", ") eng
        if (brs!="") disp = disp (disp==""?"":", ") brs }
      comp = (id in mainname) ? mainname[id] : (names[id]!="" ? names[id] : anyname[id])
      print id "\t" comp "\t" disp "\t" cls "\t" prs "\t" (nn[id]>1 ? names[id] : "")
    }
  }' "$CLAIMS" | sort -n > "$TMP/table.tsv"

main_max=$(awk -F'\t' '$4=="main" && $1>m {m=$1} END {print m+0}' "$CLAIMS")
is_taken() { awk -F'\t' -v n="$1" '$1==n {f=1} END {exit f?0:1}' "$CLAIMS"; }
claimants_of() { awk -F'\t' -v n="$1" '$1==n {print $3}' "$TMP/table.tsv"; }
component_of() { awk -F'\t' -v n="$1" '$1==n {print $2}' "$TMP/table.tsv"; }
local_check() { echo "make check-component-id ID=$1 (local tree only): $(make -s -C "$PROTOCOL" check-component-id ID="$1" 2>&1 | tail -1)"; }

# --- --check mode
if [ -n "$CHECK" ]; then
  if is_taken "$CHECK"; then
    echo "id $CHECK: taken by $(claimants_of "$CHECK") (component: $(component_of "$CHECK"))"
    local_check "$CHECK"; exit 1
  fi
  echo "id $CHECK: free (not on any origin/* branch, open PR or engine copy)"
  local_check "$CHECK"; exit 0
fi

# --- table
echo
echo "ids >= $MIN (claimants: main = origin/main; names = origin/<branch>; #N = open PR; bevy/godot/unity = engine copy)"
printf '%-6s %-30s %s\n' ID COMPONENT CLAIMANTS
awk -F'\t' -v min="$MIN" '$1>=min { printf "%-6s %-30s %s%s\n", $1, $2, $3, ($6!="" ? "  [NAME-MISMATCH " $6 "]" : "") }' "$TMP/table.tsv"

# --- next safe id: first id above main max that nobody claims anywhere
next=$((main_max + 1))
while is_taken "$next"; do next=$((next+1)); done

ranges() { # stdin: numbers -> "a-b, c, d-e"
  sort -nu | awk '{ n=$1+0; if (start=="") { start=n; prev=n; next } if (n==prev+1) { prev=n; next }
       s = s (s==""?"":", ") (start==prev ? start : start "-" prev); start=n; prev=n }
       END { if (start!="") s = s (s==""?"":", ") (start==prev ? start : start "-" prev); print s }'
}
main_ranges=$(awk -F'\t' '$4=="main" {print $1}' "$TMP/table.tsv" | ranges)
offmain_txt=$(awk -F'\t' -v min="$MIN" '$4=="offmain" && $1>=min {print $1}' "$TMP/table.tsv" | ranges)
# open-PR claims grouped by owner set, ordered by first id
pr_txt=$(awk -F'\t' -v min="$MIN" '$4=="pr" && $1>=min { ids[$5] = ids[$5] " " $1; if (!($5 in first) || $1 < first[$5]) first[$5]=$1 }
  END { for (o in ids) print first[o] "\t" o "\t" ids[o] }' "$TMP/table.tsv" | sort -n \
  | while IFS='	' read -r first owner list; do printf '%s (%s)|' "$(printf '%s\n' $list | ranges)" "$owner"; done | sed 's/|$//; s/|/, /g')

echo
echo "main ids: $main_ranges"
echo "NEXT_SAFE_ID=$next"
rationale="main max $main_max"
[ -n "$pr_txt" ] && rationale="$rationale; open PRs $pr_txt"
[ -n "$offmain_txt" ] && rationale="$rationale; off-main $offmain_txt"
echo "RATIONALE: $rationale; next free id: $next"
awk -F'\t' -v min="$MIN" '$4=="offmain" && $1>=min { print "  off-main " $1 " " $2 ": " $3 }' "$TMP/table.tsv"

# --- collisions worth shouting about (integration PRs #202/#472 always overlap each other, so they are ignored here)
awk -F'\t' '{ np=split($5, p, ",")
  if (np>1) print "WARNING: id " $1 " is claimed by more than one open PR: " $5
  if (np>0 && $5!="" && $4=="main") print "WARNING: id " $1 " (" $2 ") is already on origin/main but open PR " $5 " also adds it; that PR must renumber"
  if ($6!="") print "WARNING: id " $1 " names differ across main/open PRs/engine copies: " $6 }' "$TMP/table.tsv"

echo
local_check "$next"
exit 0
