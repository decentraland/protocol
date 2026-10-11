#!/usr/bin/env bash
# engine-support.sh - per-consumer schema status (L0) and real consumers (L1) of a protocol message
# or one of its fields, read from the fetched default branches so stale working trees do not matter.
#
# Usage: engine-support.sh <PbName|Name|proto path> [--field <snake_name>] [--repos sdk,unity,bevy,godot]
#
# L0 schema, per consumer:
#   sdk    @dcl/protocol pins in package.json and packages/@dcl/sdk-commands/package.json (origin/main,
#          plus the working tree when it differs); does the pinned protocol commit contain the proto /
#          the field (git show <sha7>:proto/<path> in the protocol repo)
#   unity  scripts/package.json pin (origin/dev); Explorer/Assets/Protocol/DecentralandProtocol/<File>.gen.cs
#          present and containing the field (PascalCase); ComponentID.gen.cs constant
#   bevy   vendored crates/dcl_component/src/proto/<path> vs protocol origin/main and origin/experimental-bevy
#          (says which it matches); stem in crates/dcl_component/build.rs; SceneComponentId const in lib.rs
#   godot  PROTOCOL_FIXED_VERSION_URL commit (src/install_dependency.rs) vs `git log -1 origin/main -- <proto>`;
#          extracted lib/src/dcl/components/proto copy (working tree); GROW_ONLY_SET_COMPONENTS entry
# L1 consumers (git grep on the fetched branch, generated dirs excluded: unity
# Explorer/Assets/Protocol/DecentralandProtocol, sdk packages/@dcl/ecs/src/components/generated and *.gen.ts,
# bevy crates/dcl_component/src/proto and target/, godot lib/src/dcl/components/proto and target/):
# hit count and top 10 path:line per repo, plus registration hits (unity ComponentsContainer.cs
# SDKComponentBuilder<PbName>, bevy add_crdt_lww_component/add_crdt_go_component/reg!, godot fn update_<snake>
# and get_<snake>, sdk GROWN_ONLY_COMPONENTS and extended/<Name>.ts). With --field the L1 grep looks for the
# field (unity `.Field`/`HasField`, bevy/godot `.snake`/`snake:`, sdk camelCase).
# Prints SCHEMA-ONLY when the schema is present but nothing consumes it. Read-only; WARNINGs for MISSING
# repos and FETCH_HEAD older than 24h. Exit 2 on usage errors.
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
usage() { awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; }
B='(^|[^A-Za-z0-9_])'; E='([^A-Za-z0-9_]|$)'

ARG=""; FIELD=""; REPOS="sdk,unity,bevy,godot"
while [ $# -gt 0 ]; do
  case "$1" in
    --field) shift; FIELD=${1:-} ;;
    --repos) shift; REPOS=${1:-} ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) ARG=$1 ;;
  esac
  shift
done
[ -n "$ARG" ] || { usage >&2; exit 2; }
want() { case ",$REPOS," in *",$1,"*) return 0 ;; esac; return 1; }

PROTOCOL=$("$SCRIPT_DIR/find-repos.sh" --path protocol) || { echo "ERROR: protocol repo not found" >&2; exit 2; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/engine-support.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT

fetch_age_hours() {
  local gp f m
  gp=$(git -C "$1" rev-parse --git-path FETCH_HEAD 2>/dev/null) || { echo never; return; }
  case "$gp" in /*) f=$gp ;; *) f="$1/$gp" ;; esac
  [ -f "$f" ] || { echo never; return; }
  m=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null) || { echo never; return; }
  echo $(( ($(date +%s) - m) / 3600 ))
}
warn_age() { local a; a=$(fetch_age_hours "$2"); if [ "$a" = never ]; then echo "WARNING: $1 never fetched"; elif [ "$a" -gt 24 ]; then echo "WARNING: $1 FETCH_HEAD is ${a}h old; fetched branch may be stale (git -C $2 fetch origin --prune)"; fi; }
warn_age protocol "$PROTOCOL"

# --- resolve file + message
REL=""; NAME=""
case "$ARG" in
  *.proto)
    REL=${ARG#proto/}
    git -C "$PROTOCOL" cat-file -e "origin/main:proto/$REL" 2>/dev/null || { echo "ERROR: proto/$REL not on origin/main" >&2; exit 2; }
    NAME=$(git -C "$PROTOCOL" show "origin/main:proto/$REL" | sed -n -E 's/^[[:space:]]*message[[:space:]]+([A-Za-z0-9_]+).*/\1/p' | head -1) ;;
  *)
    NAME=$ARG
    hits=$(git -C "$PROTOCOL" grep -l -E "^[[:space:]]*message[[:space:]]+$NAME[[:space:]]*\{?" origin/main -- proto 2>/dev/null | sed 's/^origin\/main:proto\///')
    if [ -z "$hits" ]; then hits=$(git -C "$PROTOCOL" grep -l -E "^[[:space:]]*message[[:space:]]+PB$NAME[[:space:]]*\{?" origin/main -- proto 2>/dev/null | sed 's/^origin\/main:proto\///'); [ -n "$hits" ] && NAME="PB$NAME"; fi
    [ -n "$hits" ] || { echo "ERROR: no message named $ARG (or PB$ARG) on origin/main" >&2; exit 2; }
    REL=$(printf '%s\n' "$hits" | head -1) ;;
esac
STEM=$(basename "$REL" .proto)
STEM_PASCAL=$(printf '%s' "$STEM" | awk -F_ '{ for (i=1;i<=NF;i++) printf "%s%s", toupper(substr($i,1,1)), substr($i,2) }')
STEM_UPPER=$(printf '%s' "$STEM" | tr '[:lower:]' '[:upper:]')
PASCAL=${NAME#PB}
IS_COMPONENT=0; case "$REL" in decentraland/sdk/components/common/*) ;; decentraland/sdk/components/*) IS_COMPONENT=1 ;; esac
COMP_ID=$(git -C "$PROTOCOL" show "origin/main:proto/$REL" | sed -n -E 's/.*ecs_component_id\)[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' | head -1)
FIELD_CAMEL=""; FIELD_PASCAL=""
if [ -n "$FIELD" ]; then
  FIELD_PASCAL=$(printf '%s' "$FIELD" | awk -F_ '{ for (i=1;i<=NF;i++) printf "%s%s", toupper(substr($i,1,1)), substr($i,2) }')
  FIELD_CAMEL=$(printf '%s' "$FIELD_PASCAL" | awk '{ print tolower(substr($0,1,1)) substr($0,2) }')
  git -C "$PROTOCOL" show "origin/main:proto/$REL" | grep -q -E "${B}${FIELD}[[:space:]]*=" || echo "WARNING: field '$FIELD' is not in proto/$REL on origin/main (proposal field? L0 will say missing everywhere)"
fi
echo "message: $NAME  file: proto/$REL  component id: ${COMP_ID:-n/a (not a component file)}${FIELD:+  field: $FIELD (camel $FIELD_CAMEL, pascal $FIELD_PASCAL)}"
echo "protocol origin/main: $(git -C "$PROTOCOL" rev-parse --short origin/main)  last commit touching the file: $(git -C "$PROTOCOL" log -1 --format='%h %ad' --date=short origin/main -- "proto/$REL")"

SUMMARY="$TMP/summary"; : > "$SUMMARY"
sha_of() { printf '%s' "$1" | sed -n 's/.*commit-\([0-9a-f]\{7,\}\).*/\1/p'; }
proto_at() { # <sha> -> prints "<has|differs|missing|unknown><TAB><text>"; callers split with pa_status / pa_text
  local sha=$1 out st
  if ! git -C "$PROTOCOL" cat-file -e "$sha^{commit}" 2>/dev/null; then printf "unknown\tcommit %s not in local protocol clone (fetch)\n" "$sha"; return; fi
  if git -C "$PROTOCOL" cat-file -e "$sha:proto/$REL" 2>/dev/null; then
    out="file yes"; st=has
    if [ -n "$FIELD" ]; then if git -C "$PROTOCOL" show "$sha:proto/$REL" | grep -q -E "${B}${FIELD}[[:space:]]*="; then out="$out, field $FIELD yes"; else out="$out, field $FIELD NO"; st=differs; fi; fi
    git -C "$PROTOCOL" diff --quiet "$sha" origin/main -- "proto/$REL" 2>/dev/null || out="$out (file differs from origin/main)"
  else out="file NO (pin predates proto/$REL)"; st=missing; fi
  printf "%s\t%s\n" "$st" "$out"
}
pa_status() { printf "%s" "${1%%	*}"; }
pa_text() { printf "%s" "${1#*	}"; }
ggrep() { # <dir> <ref> <pattern> <pathspec...> -> path:line:content (ref prefix stripped)
  local dir=$1 ref=$2 pat=$3; shift 3
  git -C "$dir" grep -n -I -E "$pat" "$ref" -- "$@" 2>/dev/null | sed "s|^$ref:||"
}
show_hits() { # <title> <file> (prints the listing; use count <file> for the number)
  local n; n=$(grep -c . "$2" 2>/dev/null); n=${n:-0}
  echo "  L1 $1: $n hit(s)"
  [ "$n" -gt 0 ] && head -10 "$2" | cut -c1-170 | sed "s/^/     /"
  [ "$n" -gt 10 ] && echo "     ... $((n-10)) more"
  return 0
}
count() { local n; n=$(grep -c . "$1" 2>/dev/null); printf "%s" "${n:-0}"; }
verdict() { # <repo> <l0> <consumers> <registration> <l0 detail>
  local v
  if [ "$2" = missing ]; then v="schema missing -> feasible, needs pin/vendor bump"
  elif [ "$2" = differs ]; then v="schema differs (field absent) -> feasible, needs pin/vendor bump"
  elif [ "$2" = unknown ]; then v="schema status unknown (fetch the pin commit)"
  elif [ "$3" -eq 0 ] && [ "$4" -eq 0 ]; then v="SCHEMA-ONLY (schema present, no consumer, no registration)"
  elif [ "$3" -eq 0 ]; then v="SCHEMA-ONLY${FIELD:+ for field $FIELD} (registered, but no consumer hit)"
  else v="consumed"; fi
  printf '%-7s L0 %-8s L1 consumers %-4s registration %-3s -> %s  [%s]\n' "$1" "$2" "$3" "$4" "$v" "$5" >> "$SUMMARY"
  echo "  verdict: $v"
}

# ================= sdk
if want sdk; then
  echo; SDK=$("$SCRIPT_DIR/find-repos.sh" --path js-sdk-toolchain) || SDK=""
  if [ -z "$SDK" ]; then echo "== js-sdk-toolchain: MISSING (gh repo clone decentraland/js-sdk-toolchain)"; echo "sdk     MISSING repo" >> "$SUMMARY"
  else
    warn_age js-sdk-toolchain "$SDK"; ref=origin/main
    echo "== js-sdk-toolchain ($SDK, $ref; working tree on $(git -C "$SDK" rev-parse --abbrev-ref HEAD))"
    l0=missing; detail=""
    for f in package.json packages/@dcl/sdk-commands/package.json; do
      v=$(git -C "$SDK" show "$ref:$f" 2>/dev/null | grep -o '"@dcl/protocol": *"[^"]*"' | head -1 | sed 's/.*: *"//; s/"$//')
      sha=$(sha_of "$v"); r="unknown	(no commit-<sha7> in pin)"
      [ -n "$sha" ] && r=$(proto_at "$sha")
      echo "  L0 $ref $f: ${v:-<none>} -> $(pa_text "$r")"
      [ "$f" = package.json ] && { l0=$(pa_status "$r"); detail="pin $sha: $(pa_text "$r")"; }
      w=$(cat "$SDK/$f" 2>/dev/null | grep -o '"@dcl/protocol": *"[^"]*"' | head -1 | sed 's/.*: *"//; s/"$//')
      if [ -n "$w" ] && [ "$w" != "$v" ]; then
        wsha=$(sha_of "$w"); wr="unknown	(no commit-<sha7>)"; [ -n "$wsha" ] && wr=$(proto_at "$wsha")
        flag=""; case "$w" in http*|file:*|git*) flag="  MUST REPIN BEFORE MERGE" ;; esac
        echo "  L0 working tree $f: $w$flag -> $(pa_text "$wr")"
      fi
    done
    if [ -n "$FIELD" ]; then pat="${B}${FIELD_CAMEL}${E}"; title="field $FIELD_CAMEL"; else pat="${B}(PB)?${PASCAL}${E}"; title="$PASCAL / PB$PASCAL"; fi
    ggrep "$SDK" "$ref" "$pat" packages/@dcl/ecs/src packages/@dcl/react-ecs/src packages/@dcl/sdk/src packages/@dcl/js-runtime test scripts \
      ':(exclude)packages/@dcl/ecs/src/components/generated' ':(exclude)*.gen.ts' ':(exclude)scripts/protocol-buffer-generation/generateIndex.ts' > "$TMP/sdk.hits"
    show_hits "$title (packages/@dcl/{ecs,react-ecs,sdk,js-runtime}/src, test, scripts; generated excluded)" "$TMP/sdk.hits"; n=$(count "$TMP/sdk.hits")
    go=$(git -C "$SDK" show "$ref:scripts/protocol-buffer-generation/generateIndex.ts" 2>/dev/null | grep -c "GROWN_ONLY_COMPONENTS.*'$PASCAL'")
    ext=0; git -C "$SDK" cat-file -e "$ref:packages/@dcl/ecs/src/components/extended/$PASCAL.ts" 2>/dev/null && ext=1
    echo "  L1 registration: GROWN_ONLY_COMPONENTS has '$PASCAL': $([ "$go" -gt 0 ] && echo yes || echo no); extended/$PASCAL.ts: $([ "$ext" = 1 ] && echo yes || echo no)"
    verdict sdk "$l0" "$n" "$((go+ext))" "$detail"
  fi
fi

# ================= unity
if want unity; then
  echo; UNITY=$("$SCRIPT_DIR/find-repos.sh" --path unity-explorer) || UNITY=""
  if [ -z "$UNITY" ]; then echo "== unity-explorer: MISSING (gh repo clone decentraland/unity-explorer)"; echo "unity   MISSING repo" >> "$SUMMARY"
  else
    warn_age unity-explorer "$UNITY"; ref=origin/dev; gen="Explorer/Assets/Protocol/DecentralandProtocol"
    echo "== unity-explorer ($UNITY, $ref; working tree on $(git -C "$UNITY" rev-parse --abbrev-ref HEAD))"
    v=$(git -C "$UNITY" show "$ref:scripts/package.json" 2>/dev/null | grep -o '"@dcl/protocol": *"[^"]*"' | head -1 | sed 's/.*: *"//; s/"$//')
    sha=$(sha_of "$v"); r="unknown	(no commit-<sha7>)"; [ -n "$sha" ] && r=$(proto_at "$sha")
    echo "  L0 $ref scripts/package.json: ${v:-<none>} -> $(pa_text "$r")"
    l0=$(pa_status "$r"); detail="pin $sha"
    if git -C "$UNITY" cat-file -e "$ref:$gen/$STEM_PASCAL.gen.cs" 2>/dev/null; then
      gs="$gen/$STEM_PASCAL.gen.cs present"
      if [ -n "$FIELD" ]; then if git -C "$UNITY" show "$ref:$gen/$STEM_PASCAL.gen.cs" | grep -q -E "${B}${FIELD_PASCAL}${E}"; then gs="$gs, has $FIELD_PASCAL"; [ "$l0" = missing ] && l0=has; else gs="$gs, NO $FIELD_PASCAL"; l0=differs; fi
      else [ "$l0" = missing ] && l0=has; fi
    else gs="$gen/$STEM_PASCAL.gen.cs ABSENT (npm run build-protocol after a pin bump)"; l0=missing; fi
    echo "  L0 generated: $gs"
    if [ "$IS_COMPONENT" = 1 ]; then
      cid=$(git -C "$UNITY" show "$ref:$gen/ComponentID.gen.cs" 2>/dev/null | grep -E "${B}${STEM_UPPER} *= *[0-9]+" | head -1 | sed 's/^[[:space:]]*//')
      echo "  L0 ComponentID.gen.cs: ${cid:-no constant $STEM_UPPER}${COMP_ID:+ (protocol says $COMP_ID)}"
    fi
    detail="$detail; $gs"
    if [ -n "$FIELD" ]; then pat="(\.|Has)${FIELD_PASCAL}${E}"; title="field .$FIELD_PASCAL / Has$FIELD_PASCAL (Explorer/Assets/DCL)"; spec="Explorer/Assets/DCL"; else pat="${B}PB${PASCAL}${E}"; title="PB$PASCAL (Explorer/Assets)"; spec="Explorer/Assets"; fi
    ggrep "$UNITY" "$ref" "$pat" "$spec" ":(exclude)$gen" > "$TMP/unity.hits"
    show_hits "$title, generated excluded" "$TMP/unity.hits"; n=$(count "$TMP/unity.hits")
    ggrep "$UNITY" "$ref" "SDKComponentBuilder<PB${PASCAL}>" Explorer/Assets/DCL/Infrastructure/Global/ComponentsContainer.cs > "$TMP/unity.reg"
    ggrep "$UNITY" "$ref" "partial class PB${PASCAL}${E}" Explorer/Assets/DCL/Infrastructure/ProtobufPartialClasses >> "$TMP/unity.reg"
    r=$(count "$TMP/unity.reg"); echo "  L1 registration (ComponentsContainer.cs builder, IDirtyMarker partial): $r hit(s)"; head -5 "$TMP/unity.reg" | cut -c1-170 | sed 's/^/     /'
    verdict unity "$l0" "$n" "$r" "$detail"
  fi
fi

# ================= bevy
if want bevy; then
  echo; BEVY=$("$SCRIPT_DIR/find-repos.sh" --path bevy-explorer) || BEVY=""
  if [ -z "$BEVY" ]; then echo "== bevy-explorer: MISSING (gh repo clone decentraland/bevy-explorer)"; echo "bevy    MISSING repo" >> "$SUMMARY"
  else
    warn_age bevy-explorer "$BEVY"; ref=origin/main; vend="crates/dcl_component/src/proto/$REL"
    echo "== bevy-explorer ($BEVY, $ref; working tree on $(git -C "$BEVY" rev-parse --abbrev-ref HEAD))"
    l0=missing; detail=""
    if git -C "$BEVY" show "$ref:$vend" > "$TMP/bevy.proto" 2>/dev/null; then
      m=""; for b in main experimental-bevy protocol-squad; do git -C "$PROTOCOL" show "origin/$b:proto/$REL" > "$TMP/b.proto" 2>/dev/null && cmp -s "$TMP/bevy.proto" "$TMP/b.proto" && m="$m $b"; done
      if [ -n "$m" ]; then vs="matches protocol origin:$m"; else
        dm=$(git -C "$PROTOCOL" show origin/main:proto/$REL 2>/dev/null | diff - "$TMP/bevy.proto" | grep -c '^[<>]'); de=$(git -C "$PROTOCOL" show origin/experimental-bevy:proto/$REL 2>/dev/null | diff - "$TMP/bevy.proto" | grep -c '^[<>]')
        vs="matches neither main nor experimental-bevy (differing lines: main $dm, experimental-bevy $de)"; fi
      l0=has
      if [ -n "$FIELD" ]; then if grep -q -E "${B}${FIELD}[[:space:]]*=" "$TMP/bevy.proto"; then vs="$vs; has field $FIELD"; else vs="$vs; NO field $FIELD"; l0=differs; fi; fi
      echo "  L0 vendored $vend: $vs"
    else echo "  L0 vendored $vend: ABSENT (copy the file from the target protocol branch)"; vs="not vendored"; fi
    detail="$vs"
    if [ "$IS_COMPONENT" = 1 ]; then
      bs=$(git -C "$BEVY" show "$ref:crates/dcl_component/build.rs" 2>/dev/null | grep -c "\"$STEM\"")
      cst=$(git -C "$BEVY" show "$ref:crates/dcl_component/src/lib.rs" 2>/dev/null | grep -E "SceneComponentId\(${COMP_ID:-NONE}\)" | head -1 | sed 's/^[[:space:]]*//')
      echo "  L0 build.rs stem \"$STEM\": $([ "$bs" -gt 0 ] && echo yes || echo NO); SceneComponentId($COMP_ID) const: ${cst:-NONE}"
      [ "$bs" -gt 0 ] && [ -n "$cst" ] || { [ "$l0" = has ] && l0=differs; detail="$detail; build.rs/const incomplete"; }
    fi
    if [ -n "$FIELD" ]; then pat="\.${FIELD}${E}|${B}${FIELD}:"; title="field .$FIELD / $FIELD: (crates)"; else pat="${B}Pb${PASCAL}${E}"; title="Pb$PASCAL (crates)"; fi
    ggrep "$BEVY" "$ref" "$pat" crates ":(exclude)crates/dcl_component/src/proto" ":(exclude)target" > "$TMP/bevy.hits"
    show_hits "$title, vendored protos excluded" "$TMP/bevy.hits"; n=$(count "$TMP/bevy.hits")
    ggrep "$BEVY" "$ref" "add_crdt_lww_component::<Pb${PASCAL}${E}|add_crdt_go_component::<Pb${PASCAL}${E}|reg!\(Pb${PASCAL}${E}" crates > "$TMP/bevy.reg"
    r=$(count "$TMP/bevy.reg"); echo "  L1 registration (add_crdt_lww_component / add_crdt_go_component / reg!): $r hit(s)"; head -5 "$TMP/bevy.reg" | cut -c1-170 | sed 's/^/     /'
    verdict bevy "$l0" "$n" "$r" "$detail"
  fi
fi

# ================= godot
if want godot; then
  echo; GODOT=$("$SCRIPT_DIR/find-repos.sh" --path godot-explorer) || GODOT=""
  if [ -z "$GODOT" ]; then echo "== godot-explorer: MISSING (gh repo clone decentraland/godot-explorer)"; echo "godot   MISSING repo" >> "$SUMMARY"
  else
    warn_age godot-explorer "$GODOT"; ref=origin/main
    echo "== godot-explorer ($GODOT, $ref; working tree on $(git -C "$GODOT" rev-parse --abbrev-ref HEAD))"
    url=$(git -C "$GODOT" show "$ref:src/install_dependency.rs" 2>/dev/null | awk '/PROTOCOL_FIXED_VERSION_URL: *Option<&str> *=/ { buf=$0; for (i=0;i<3 && buf !~ /;/;i++) { getline l; buf = buf l } if (buf ~ /None/) { print "None"; exit } if (match(buf, /"[^"]*"/)) { print substr(buf, RSTART+1, RLENGTH-2); exit } }')
    last=$(git -C "$PROTOCOL" log -1 --format=%h origin/main -- "proto/$REL")
    if [ "$url" = None ]; then echo "  L0 PROTOCOL_FIXED_VERSION_URL = None -> npm 'next' at install time (contents depend on when install ran)"; l0=unknown; detail="pin None (npm next)"
    else
      sha=$(sha_of "$url"); r="unknown	(no commit-<sha7>)"; [ -n "$sha" ] && r=$(proto_at "$sha"); st=$(pa_text "$r")
      flag=""; case "$url" in *sdk-team-cdn*) flag="  MUST REPIN BEFORE MERGE" ;; esac
      echo "  L0 PROTOCOL_FIXED_VERSION_URL: $url$flag"
      if [ -n "$sha" ] && git -C "$PROTOCOL" cat-file -e "$sha^{commit}" 2>/dev/null; then
        if git -C "$PROTOCOL" merge-base --is-ancestor "$last" "$sha" 2>/dev/null; then cur="contains the last commit touching the file ($last): yes"; else cur="contains the last commit touching the file ($last): NO (pin is $(git -C "$PROTOCOL" rev-list --count "$sha..origin/main") commits behind origin/main)"; fi
      else cur="pin commit not resolvable locally"; fi
      echo "  L0 pin commit $sha: $st; $cur"
      l0=$(pa_status "$r"); detail="pin $sha: $st"
    fi
    if [ -f "$GODOT/lib/src/dcl/components/proto/$REL" ]; then
      es="extracted copy present (working tree)"
      if [ -n "$FIELD" ]; then if grep -q -E "${B}${FIELD}[[:space:]]*=" "$GODOT/lib/src/dcl/components/proto/$REL"; then es="$es, has field $FIELD"; else es="$es, NO field $FIELD"; fi; fi
    elif [ -d "$GODOT/lib/src/dcl/components/proto" ]; then es="extracted copy ABSENT for this file (pin predates it, or re-run cargo run -- install)"
    else es="protos not extracted (cargo run -- install)"; fi
    echo "  L0 lib/src/dcl/components/proto/$REL: $es"
    if [ "$IS_COMPONENT" = 1 ]; then
      g=$(git -C "$GODOT" show "$ref:lib/build.rs" 2>/dev/null | grep -c "\"$PASCAL\"")
      echo "  L0 GROW_ONLY_SET_COMPONENTS has \"$PASCAL\": $([ "$g" -gt 0 ] && echo yes || echo no) (LWW unless listed)"
    fi
    if [ -n "$FIELD" ]; then pat="\.${FIELD}${E}|${B}${FIELD}:"; title="field .$FIELD / $FIELD: (lib/src)"; else pat="${B}Pb${PASCAL}${E}|get_${STEM}${E}"; title="Pb$PASCAL / get_$STEM (lib/src)"; fi
    ggrep "$GODOT" "$ref" "$pat" lib/src ":(exclude)lib/src/dcl/components/proto" ":(exclude)target" > "$TMP/godot.hits"
    if [ -n "$FIELD" ]; then ggrep "$GODOT" "$ref" "${B}(${FIELD}|${FIELD_CAMEL})${E}" godot/src >> "$TMP/godot.hits"; title="$title + $FIELD/$FIELD_CAMEL (godot/src GDScript)"; fi
    show_hits "$title, extracted protos excluded" "$TMP/godot.hits"; n=$(count "$TMP/godot.hits")
    ggrep "$GODOT" "$ref" "fn update_${STEM}${E}" lib/src > "$TMP/godot.reg"
    ggrep "$GODOT" "$ref" "get_${STEM}${E}" lib/src ":(exclude)lib/src/dcl/components/proto" >> "$TMP/godot.reg2"
    r=$(count "$TMP/godot.reg"); r2=$(count "$TMP/godot.reg2")
    echo "  L1 registration: fn update_$STEM: $r hit(s); get_$STEM accessor uses: $r2"; head -3 "$TMP/godot.reg" | cut -c1-170 | sed 's/^/     /'
    verdict godot "$l0" "$n" "$((r+r2))" "$detail"
  fi
fi

echo
echo "SUMMARY ($NAME${FIELD:+ field $FIELD}; L0 = schema in the consumer's pin/copy, L1 = non-generated consumers on the fetched branch)"
sed 's/^/  /' "$SUMMARY"
exit 0
