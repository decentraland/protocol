#!/usr/bin/env bash
# proposal-gate.sh - enforce the phase order of a protocol-feature proposal bundle, and list bundles.
#
# Usage:
#   proposal-gate.sh <proposal.md> <phase 1..6> [--dry-run]
#   proposal-gate.sh status [slug] [--dir <bundles dir>]
#
# Gate mode validates the YAML frontmatter (keys title, slug, kind, size, mode, draft, phase, status,
# target_branch, component, owner, created, updated, nested policy: and links:), then the `## Gate log`
# table rows `| <n> <name> | <passed|pending|failed|waived> | <date> | <by> | <evidence> |`:
#   - phase N may run only if gates 1..N-1 are `passed`, or `waived` with a non-empty `by`
#   - size: small may keep gate 3 `pending` (L2 runtime observation); it is logged, not blocking
#   - --dry-run refuses `mode: execute`
#   - the section for phase N must exist: 1 `## 1. Need`, 2 `## 2. Design`, 3 `## 3. Technology
#     verification`, 4 `## 4. Definition`, 5 `## 5. Implementation`, 6 `## 6. Review`
#     (`## 1-2. Need and design` is accepted for phases 1 and 2, small track)
# Prints `OK: may run phase N` (exit 0) or `BLOCKED: <first violated rule>` (exit 1); exit 2 on
# usage/parse errors (missing file, no frontmatter, bad phase argument).
#
# status mode lists every bundle (<dir>/*/proposal.md, dir = --dir, else $PROTOCOL_FEATURE_OUT, else
# ./proposals) with slug, status, size, kind, mode, phase, next phase and the empty `links:` entries;
# with a slug it prints a 5-line resume card. Read-only.
set -u

usage() { awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/proposal-gate.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT

# ---------- frontmatter + body helpers (grep/sed/awk only)
load() { # <proposal.md> -> $TMP/fm (frontmatter lines) and $TMP/body ; returns 1 when no frontmatter
  awk 'NR==1 { if ($0 !~ /^---[ \t\r]*$/) exit 1; next } /^---[ \t\r]*$/ { exit 0 } { print }' "$1" > "$TMP/fm" || return 1
  awk 'NR==1 { next } found { print; next } /^---[ \t\r]*$/ { found=1 }' "$1" > "$TMP/body"
  [ -s "$TMP/fm" ] || return 1
  return 0
}
fm_get() { # <key> -> top-level scalar value (quotes and trailing # comments stripped)
  awk -v k="$1" 'index($0, k ":")==1 { v=substr($0, length(k)+2); sub(/[ \t]+#.*$/, "", v); gsub(/^[ \t]+|[ \t\r]+$/, "", v); gsub(/^["'"'"']|["'"'"']$/, "", v); print v; exit }' "$TMP/fm"
}
fm_has_map() { grep -q -E "^$1:[[:space:]]*(#.*)?$" "$TMP/fm"; }
fm_map_entries() { # <map key> -> "subkey<TAB>value" lines
  awk -v k="$1" 'index($0, k ":")==1 { inmap=1; next } inmap && /^[^ \t#]/ { inmap=0 } inmap && /^[ \t]+[A-Za-z_][A-Za-z0-9_]*:/ { l=$0; sub(/^[ \t]+/, "", l); i=index(l, ":"); key=substr(l,1,i-1); v=substr(l,i+1); sub(/[ \t]+#.*$/, "", v); gsub(/^[ \t]+|[ \t\r]+$/, "", v); print key "\t" v }' "$TMP/fm"
}
gate_rows() { # -> "n<TAB>name<TAB>result<TAB>date<TAB>by<TAB>evidence"
  awk 'BEGIN{IGNORECASE=1} /^## Gate log/ { ing=1; next } ing && /^## / { ing=0 } ing && /^\|/ {
      n=split($0, c, "|"); for (i=1;i<=n;i++) gsub(/^[ \t]+|[ \t\r]+$/, "", c[i])
      if (c[2] ~ /^[0-9]+[ \t]/) { g=c[2]; sub(/[ \t].*$/, "", g); nm=c[2]; sub(/^[0-9]+[ \t]+/, "", nm); print g "\t" nm "\t" tolower(c[3]) "\t" c[4] "\t" c[5] "\t" c[6] } }' "$TMP/body"
}
gate_names() { case "$1" in 1) echo need ;; 2) echo design ;; 3) echo tech-check ;; 4) echo define ;; 5) echo implement ;; 6) echo review ;; esac; }
section_present() { # <phase>
  case "$1" in
    1) grep -q -E '^## (1\. Need|1-2\. Need)' "$TMP/body" ;;
    2) grep -q -E '^## (2\. Design|1-2\. Need)' "$TMP/body" ;;
    3) grep -q -E '^## 3\. Technology verification' "$TMP/body" ;;
    4) grep -q -E '^## 4\. Definition' "$TMP/body" ;;
    5) grep -q -E '^## 5\. Implementation' "$TMP/body" ;;
    6) grep -q -E '^## 6\. Review' "$TMP/body" ;;
  esac
}
in_set() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

# next phase = first gate whose row is not passed/waived(by) (small: gate 3 pending counts as done)
next_phase() { # <size> -> number or "done"
  local size=$1 g res by
  for g in 1 2 3 4 5 6; do
    row=$(gate_rows | awk -F'\t' -v g="$g" '$1==g' | head -1)
    [ -n "$row" ] || { echo "$g"; return; }
    res=$(printf '%s' "$row" | cut -f3); by=$(printf '%s' "$row" | cut -f5)
    case "$res" in
      passed) ;;
      waived) [ -n "$by" ] || { echo "$g"; return; } ;;
      pending) if [ "$size" = small ] && [ "$g" = 3 ]; then :; else echo "$g"; return; fi ;;
      *) echo "$g"; return ;;
    esac
  done
  echo done
}

# ---------- status mode
if [ "${1:-}" = status ]; then
  shift; SLUG=""; DIR=""
  while [ $# -gt 0 ]; do case "$1" in --dir) shift; DIR=${1:-} ;; -h|--help) usage; exit 0 ;; *) SLUG=$1 ;; esac; shift; done
  [ -n "$DIR" ] || DIR=${PROTOCOL_FEATURE_OUT:-proposals}
  [ -d "$DIR" ] || { echo "no bundles: directory '$DIR' does not exist (set --dir or PROTOCOL_FEATURE_OUT)"; exit 0; }
  found=0
  if [ -z "$SLUG" ]; then printf '%-28s %-12s %-7s %-16s %-8s %-6s %-5s %s\n' SLUG STATUS SIZE KIND MODE PHASE NEXT EMPTY_LINKS; fi
  for p in "$DIR"/*/proposal.md; do
    [ -f "$p" ] || continue
    d=$(basename "$(dirname "$p")")
    if ! load "$p"; then [ -n "$SLUG" ] && [ "$SLUG" != "$d" ] || echo "$d: WARNING: no frontmatter in $p"; continue; fi
    slug=$(fm_get slug); [ -n "$slug" ] || slug=$d
    [ -z "$SLUG" ] || [ "$SLUG" = "$slug" ] || [ "$SLUG" = "$d" ] || continue
    found=$((found+1))
    status=$(fm_get status); size=$(fm_get size); kind=$(fm_get kind); mode=$(fm_get mode); phase=$(fm_get phase)
    nxt=$(next_phase "$size")
    empty=$(fm_map_entries links | awk -F'\t' '$2=="" { printf "%s%s", (s++?",":""), $1 }')
    filled=$(fm_map_entries links | awk -F'\t' '$2!="" { printf "%s%s", (s++?",":""), $1 }')
    if [ -z "$SLUG" ]; then
      printf '%-28s %-12s %-7s %-16s %-8s %-6s %-5s %s\n' "$slug" "${status:-?}" "${size:-?}" "${kind:-?}" "${mode:-?}" "${phase:-?}" "$nxt" "${empty:--}"
    else
      gates=$(gate_rows | awk -F'\t' '{ printf "%s%s %s%s", (s++?", ":""), $1, $3, ($5!=""?" ("$5")":"") }')
      echo "$slug - $(fm_get title) [$kind/$size/$mode, draft=$(fm_get draft), target $(fm_get target_branch), component $(fm_get component)]"
      echo "status: ${status:-?}; frontmatter phase: ${phase:-?}; next phase to run: $nxt$( [ "$nxt" != done ] && echo " ($(gate_names "$nxt"))")"
      echo "gates: ${gates:-no Gate log rows}"
      echo "links filled: ${filled:--}; empty: ${empty:--}"
      echo "resume: $0 $p $nxt$( [ "$mode" = plan ] && echo " --dry-run")   (owner ${owner:-$(fm_get owner)}, created $(fm_get created), updated $(fm_get updated))"
    fi
  done
  [ "$found" -gt 0 ] || { if [ -n "$SLUG" ]; then echo "no bundle with slug '$SLUG' under $DIR"; else echo "no bundles under $DIR"; fi; }
  exit 0
fi

# ---------- gate mode
FILE=""; PHASE=""; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) if [ -z "$FILE" ]; then FILE=$1; elif [ -z "$PHASE" ]; then PHASE=$1; else echo "ERROR: too many arguments" >&2; exit 2; fi ;;
  esac
  shift
done
[ -n "$FILE" ] && [ -n "$PHASE" ] || { usage >&2; exit 2; }
[ -f "$FILE" ] || { echo "ERROR: $FILE not found" >&2; exit 2; }
case "$PHASE" in 1|2|3|4|5|6) ;; *) echo "ERROR: phase must be 1..6 (got '$PHASE')" >&2; exit 2 ;; esac
load "$FILE" || { echo "ERROR: $FILE has no YAML frontmatter (--- block at the top)" >&2; exit 2; }

NOTES=""
note() { NOTES="$NOTES  NOTE: $1"$'\n'; }
blocked() { printf '%s' "$NOTES"; echo "BLOCKED: $1"; exit 1; }

# frontmatter keys and enum values
for k in title slug kind size mode draft phase status target_branch component owner created updated; do
  v=$(fm_get "$k"); [ -n "$v" ] || blocked "frontmatter key '$k' is missing or empty"
done
fm_has_map policy || blocked "frontmatter has no 'policy:' map"
fm_has_map links || blocked "frontmatter has no 'links:' map"
kind=$(fm_get kind); size=$(fm_get size); mode=$(fm_get mode); draft=$(fm_get draft); phase=$(fm_get phase); status=$(fm_get status); target=$(fm_get target_branch)
in_set "$kind" "field enum-value semantics component result-component api comms none" || blocked "kind '$kind' is not one of field|enum-value|semantics|component|result-component|api|comms|none"
in_set "$size" "small medium large" || blocked "size '$size' is not one of small|medium|large"
in_set "$mode" "plan execute" || blocked "mode '$mode' is not one of plan|execute"
in_set "$draft" "true false" || blocked "draft '$draft' is not true|false"
in_set "$phase" "1 2 3 4 5 6 done" || blocked "phase '$phase' is not 1-6 or done"
in_set "$status" "draft designed verified defined implementing in-review done rejected blocked parked" || blocked "status '$status' is not a known status"
in_set "$target" "main experimental-bevy" || blocked "target_branch '$target' is not main|experimental-bevy"
for k in created updated; do v=$(fm_get "$k"); printf '%s' "$v" | grep -q -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || note "$k '$v' is not YYYY-MM-DD"; done

# mode / status rules
[ "$DRY" = 1 ] && [ "$mode" = execute ] && blocked "--dry-run refuses mode: execute (set mode: plan or drop --dry-run)"
case "$status" in rejected|blocked|parked) blocked "status is '$status'; reopen the proposal (status: draft/designed/...) before running a phase" ;; esac
[ "$status" = done ] && blocked "status is done; nothing left to run"
[ "$phase" = done ] && blocked "phase is done; nothing left to run"
if [ "$phase" != done ] && [ "$PHASE" -gt $((phase + 1)) ]; then note "frontmatter phase is $phase but phase $PHASE was requested (gate log decides)"; fi
[ "$mode" = execute ] && [ "$PHASE" -ge 5 ] && [ "$phase" != done ] && [ "$phase" -lt 4 ] && note "execute mode with sibling-repo edits expects a bundle at phase >= 4 (frontmatter says $phase)"

# gate rows 1..N-1
gate_rows > "$TMP/gates"
g=1
while [ "$g" -lt "$PHASE" ]; do
  row=$(awk -F'\t' -v g="$g" '$1==g' "$TMP/gates" | head -1)
  [ -n "$row" ] || blocked "Gate log has no row for gate $g ($(gate_names "$g"))"
  res=$(printf '%s' "$row" | cut -f3); by=$(printf '%s' "$row" | cut -f5)
  case "$res" in
    passed) ;;
    waived) [ -n "$by" ] || blocked "gate $g ($(gate_names "$g")) is waived without a 'by' (who waived it?)" ; note "gate $g waived by $by" ;;
    pending) if [ "$size" = small ] && [ "$g" = 3 ]; then note "small track: gate 3 (tech-check) is pending on L2 runtime observation; allowed, logged"; else blocked "gate $g ($(gate_names "$g")) is pending; phase $PHASE needs gates 1..$((PHASE-1)) passed"; fi ;;
    failed) blocked "gate $g ($(gate_names "$g")) failed" ;;
    "") blocked "gate $g ($(gate_names "$g")) has an empty result" ;;
    *) blocked "gate $g ($(gate_names "$g")) has unknown result '$res' (passed|pending|failed|waived)" ;;
  esac
  g=$((g+1))
done

section_present "$PHASE" || blocked "section for phase $PHASE is missing (expected '## $PHASE. ...' heading)"
printf '%s' "$NOTES"
echo "OK: may run phase $PHASE ($(gate_names "$PHASE")) on $(fm_get slug) [$kind/$size/$mode${DRY:+, dry-run}]"
exit 0
