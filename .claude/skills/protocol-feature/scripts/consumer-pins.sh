#!/usr/bin/env bash
# consumer-pins.sh - which @dcl/protocol build each consumer is pinned to, and whether it contains
# a given protocol commit / proto file.
#
# Usage: consumer-pins.sh [--commit <sha>] [--proto <path>]... [--no-npm]
#
# Prints, per consumer (fetched default branch AND the working tree when it differs):
#   js-sdk-toolchain  package.json and packages/@dcl/sdk-commands/package.json
#   unity-explorer    scripts/package.json
#   godot-explorer    PROTOCOL_FIXED_VERSION_URL in src/install_dependency.rs (None = npm `next`)
#   bevy-explorer     vendored crates/dcl_component/src/proto: which protocol branch it matches
# Every `1.0.0-<runId>.commit-<sha7>` pin is resolved to the sha; `contains <commit>? yes/no` is
# answered with `git merge-base --is-ancestor` in the protocol repo (default commit: origin/main
# HEAD, so the answer is "is this pin current?"). `--proto <path>` adds whether the pinned build
# has that file and whether it equals origin/main.
# Flags `http(s):`/`file:`/`git:` pins in the SDK package.json files and any sdk-team-cdn URL in
# godot as `MUST REPIN BEFORE MERGE` (CI check-local-deps / per-PR tarballs). Ends with
# `npm view @dcl/protocol dist-tags --json` unless --no-npm.
# WARNINGs for MISSING repos, FETCH_HEAD older than 24h, pin commits not fetched. Read-only.
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
usage() { awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; }

COMMIT=""; PROTOS=""; NO_NPM=0
while [ $# -gt 0 ]; do
  case "$1" in
    --commit) shift; COMMIT=${1:-} ;;
    --proto) shift; PROTOS="$PROTOS ${1#proto/}" ;;
    --no-npm) NO_NPM=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

PROTOCOL=$("$SCRIPT_DIR/find-repos.sh" --path protocol) || { echo "ERROR: protocol repo not found" >&2; exit 2; }

fetch_age_hours() {
  local gp f m
  gp=$(git -C "$1" rev-parse --git-path FETCH_HEAD 2>/dev/null) || { echo never; return; }
  case "$gp" in /*) f=$gp ;; *) f="$1/$gp" ;; esac
  [ -f "$f" ] || { echo never; return; }
  m=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null) || { echo never; return; }
  echo $(( ($(date +%s) - m) / 3600 ))
}
warn_age() { # <repo> <dir>
  local a; a=$(fetch_age_hours "$2")
  if [ "$a" = never ]; then echo "WARNING: $1 never fetched; origin refs may be missing"
  elif [ "$a" -gt 24 ]; then echo "WARNING: $1 FETCH_HEAD is ${a}h old; fetched branch may be stale (git -C $2 fetch origin --prune)"; fi
}
warn_age protocol "$PROTOCOL"

main_sha=$(git -C "$PROTOCOL" rev-parse --short origin/main 2>/dev/null || echo "?")
if [ -z "$COMMIT" ]; then COMMIT=$main_sha; echo "protocol: $PROTOCOL  origin/main=$main_sha  (no --commit given: 'contains' is checked against origin/main HEAD)"
else
  git -C "$PROTOCOL" cat-file -e "$COMMIT^{commit}" 2>/dev/null || { echo "ERROR: commit $COMMIT is not in the local protocol clone" >&2; exit 2; }
  echo "protocol: $PROTOCOL  origin/main=$main_sha  checking contains $COMMIT"
fi

sha_of() { printf '%s' "$1" | sed -n 's/.*commit-\([0-9a-f]\{7,\}\).*/\1/p'; }

describe_sha() { # <sha7> -> lines about the pin commit
  local sha=$1 behind ans
  if ! git -C "$PROTOCOL" cat-file -e "$sha^{commit}" 2>/dev/null; then
    echo "      WARNING: pin commit $sha is not in the local protocol clone (git fetch origin); cannot answer contains/behind"; return
  fi
  behind=$(git -C "$PROTOCOL" rev-list --count "$sha..origin/main" 2>/dev/null || echo "?")
  if git -C "$PROTOCOL" merge-base --is-ancestor "$COMMIT" "$sha" 2>/dev/null; then ans=yes; else ans=no; fi
  echo "      pin commit $sha: $(git -C "$PROTOCOL" log -1 --format='%ad %s' --date=short "$sha" 2>/dev/null | cut -c1-80); behind origin/main by $behind; contains $COMMIT? $ans"
  for p in $PROTOS; do
    if git -C "$PROTOCOL" cat-file -e "$sha:proto/$p" 2>/dev/null; then
      if git -C "$PROTOCOL" diff --quiet "$sha" origin/main -- "proto/$p" 2>/dev/null; then echo "      proto/$p: present, identical to origin/main"
      else echo "      proto/$p: present, DIFFERS from origin/main ($(git -C "$PROTOCOL" diff --numstat "$sha" origin/main -- "proto/$p" | awk '{print "+" $1 " -" $2}'))"; fi
    else echo "      proto/$p: ABSENT in the pinned build"; fi
  done
}

pin_line() { # <label> <value> <kind: sdk|unity|godot>
  local v=$2 sha flag=""
  case "${3:-sdk}" in
    sdk) case "$v" in http://*|https://*|file:*|git:*|git+*) flag="  MUST REPIN BEFORE MERGE (URL/file pin; js-sdk-toolchain CI check-local-deps rejects it)" ;; esac ;;
    *)   case "$v" in *sdk-team-cdn*) flag="  MUST REPIN BEFORE MERGE (per-PR CDN tarball, not a published build)" ;; esac ;;
  esac
  echo "    $1: $v$flag"
  sha=$(sha_of "$v")
  if [ -n "$sha" ]; then describe_sha "$sha"; else echo "      (no commit-<sha7> in the pin; cannot resolve)"; fi
}

json_pin() { # <dir> <ref|wt> <file> -> value or empty
  if [ "$2" = wt ]; then cat "$1/$3" 2>/dev/null; else git -C "$1" show "$2:$3" 2>/dev/null; fi | grep -o '"@dcl/protocol": *"[^"]*"' | head -1 | sed 's/.*: *"//; s/"$//'
}

# --- js-sdk-toolchain
SDK=$("$SCRIPT_DIR/find-repos.sh" --path js-sdk-toolchain) || SDK=""
echo
if [ -z "$SDK" ]; then echo "== js-sdk-toolchain: MISSING (gh repo clone decentraland/js-sdk-toolchain)"
else
  warn_age js-sdk-toolchain "$SDK"
  echo "== js-sdk-toolchain ($SDK; working tree on $(git -C "$SDK" rev-parse --abbrev-ref HEAD))"
  for f in package.json packages/@dcl/sdk-commands/package.json; do
    m=$(json_pin "$SDK" origin/main "$f"); w=$(json_pin "$SDK" wt "$f")
    echo "  origin/main $f"; pin_line "pin" "${m:-<none>}"
    if [ "$w" != "$m" ]; then echo "  working tree $f (differs from origin/main)"; pin_line "pin" "${w:-<none>}"; fi
  done
fi

# --- unity-explorer
UNITY=$("$SCRIPT_DIR/find-repos.sh" --path unity-explorer) || UNITY=""
echo
if [ -z "$UNITY" ]; then echo "== unity-explorer: MISSING (gh repo clone decentraland/unity-explorer)"
else
  warn_age unity-explorer "$UNITY"
  echo "== unity-explorer ($UNITY; working tree on $(git -C "$UNITY" rev-parse --abbrev-ref HEAD))"
  m=$(json_pin "$UNITY" origin/dev scripts/package.json); w=$(json_pin "$UNITY" wt scripts/package.json)
  echo "  origin/dev scripts/package.json"; pin_line "pin" "${m:-<none>}" unity
  if [ "$w" != "$m" ]; then echo "  working tree scripts/package.json (differs from origin/dev)"; pin_line "pin" "${w:-<none>}" unity; fi
  # the lockfile and the committed .gen.cs must agree with the pin
  lock=$(git -C "$UNITY" show origin/dev:scripts/package-lock.json 2>/dev/null | grep -o '"node_modules/@dcl/protocol": *{[^}]*"version": *"[^"]*"' | head -1 | sed 's/.*"version": *"//; s/"$//')
  [ -n "$lock" ] && echo "    origin/dev scripts/package-lock.json resolved version: $lock"
fi

# --- godot-explorer
GODOT=$("$SCRIPT_DIR/find-repos.sh" --path godot-explorer) || GODOT=""
echo
godot_pin() { # <dir> <ref|wt> -> URL, "None", or empty
  local src
  if [ "$2" = wt ]; then src=$(cat "$1/src/install_dependency.rs" 2>/dev/null); else src=$(git -C "$1" show "$2:src/install_dependency.rs" 2>/dev/null); fi
  printf '%s\n' "$src" | awk '/PROTOCOL_FIXED_VERSION_URL: *Option<&str> *=/ { buf=$0; for (i=0;i<3 && buf !~ /;/;i++) { getline l; buf = buf l } 
      if (buf ~ /None/) { print "None"; exit } if (match(buf, /"[^"]*"/)) { print substr(buf, RSTART+1, RLENGTH-2); exit } }'
}
if [ -z "$GODOT" ]; then echo "== godot-explorer: MISSING (gh repo clone decentraland/godot-explorer)"
else
  warn_age godot-explorer "$GODOT"
  echo "== godot-explorer ($GODOT; working tree on $(git -C "$GODOT" rev-parse --abbrev-ref HEAD))"
  m=$(godot_pin "$GODOT" origin/main); w=$(godot_pin "$GODOT" wt)
  echo "  origin/main src/install_dependency.rs"
  if [ "$m" = None ]; then echo "    PROTOCOL_FIXED_VERSION_URL = None -> resolves npm dist-tag 'next' at install time (see npm dist-tags below)"; else pin_line "PROTOCOL_FIXED_VERSION_URL" "${m:-<not found>}" godot; fi
  if [ "$w" != "$m" ]; then echo "  working tree (differs from origin/main)"; if [ "$w" = None ]; then echo "    PROTOCOL_FIXED_VERSION_URL = None -> npm 'next'"; else pin_line "PROTOCOL_FIXED_VERSION_URL" "${w:-<not found>}" godot; fi; fi
  if [ -d "$GODOT/lib/src/dcl/components/proto" ]; then
    n=$(ls "$GODOT/lib/src/dcl/components/proto/decentraland/sdk/components/"*.proto 2>/dev/null | wc -l | tr -d ' ')
    echo "    extracted copy present: lib/src/dcl/components/proto ($n sdk/components files; gitignored, reflects the last 'cargo run -- install')"
  else echo "    extracted copy absent: run 'cargo run -- install' to populate lib/src/dcl/components/proto"; fi
fi

# --- bevy-explorer (vendored)
BEVY=$("$SCRIPT_DIR/find-repos.sh" --path bevy-explorer) || BEVY=""
echo
if [ -z "$BEVY" ]; then echo "== bevy-explorer: MISSING (gh repo clone decentraland/bevy-explorer)"
else
  warn_age bevy-explorer "$BEVY"
  echo "== bevy-explorer ($BEVY; vendored protos in crates/dcl_component/src/proto, compared on origin/main)"
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/consumer-pins.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
  files=$(git -C "$BEVY" ls-tree -r --name-only origin/main -- crates/dcl_component/src/proto/decentraland/sdk/components 2>/dev/null | grep '\.proto$')
  total=0
  for b in main experimental-bevy protocol-squad; do eval "same_$(printf '%s' "$b" | tr '-' '_')=0"; done
  for f in $files; do
    rel=${f#crates/dcl_component/src/proto/}
    total=$((total+1))
    git -C "$BEVY" show "origin/main:$f" > "$TMP/bevy" 2>/dev/null || continue
    for b in main experimental-bevy protocol-squad; do
      v=$(printf '%s' "$b" | tr '-' '_')
      if git -C "$PROTOCOL" show "origin/$b:proto/$rel" > "$TMP/branch" 2>/dev/null && cmp -s "$TMP/bevy" "$TMP/branch"; then eval "same_$v=\$((same_$v+1))"; fi
    done
  done
  echo "    sdk/components files vendored: $total; byte-identical to origin/main: $same_main, origin/experimental-bevy: $same_experimental_bevy, origin/protocol-squad: $same_protocol_squad"
  best=main; bestn=$same_main
  [ "$same_experimental_bevy" -gt "$bestn" ] && { best=experimental-bevy; bestn=$same_experimental_bevy; }
  [ "$same_protocol_squad" -gt "$bestn" ] && { best=protocol-squad; bestn=$same_protocol_squad; }
  echo "    closest protocol branch: origin/$best ($bestn/$total identical)"
  for p in $PROTOS; do
    if git -C "$BEVY" show "origin/main:crates/dcl_component/src/proto/$p" > "$TMP/bevy" 2>/dev/null; then
      m=""; for b in main experimental-bevy protocol-squad; do git -C "$PROTOCOL" show "origin/$b:proto/$p" > "$TMP/branch" 2>/dev/null && cmp -s "$TMP/bevy" "$TMP/branch" && m="$m $b"; done
      if [ -n "$m" ]; then echo "    proto/$p: vendored; byte-identical to origin branch(es):$m"
      else d=""; for b in main experimental-bevy protocol-squad; do git -C "$PROTOCOL" show "origin/$b:proto/$p" > "$TMP/branch" 2>/dev/null && d="$d $b:$(diff "$TMP/branch" "$TMP/bevy" | grep -c "^[<>]")"; done; echo "    proto/$p: vendored; identical to none of main/experimental-bevy/protocol-squad (differing lines per branch:$d)"; fi
    else echo "    proto/$p: NOT vendored in bevy"; fi
  done
fi

# --- npm dist-tags
echo
if [ "$NO_NPM" = 1 ]; then echo "npm dist-tags: skipped (--no-npm)"
elif command -v npm >/dev/null 2>&1; then
  echo "npm view @dcl/protocol dist-tags --json:"
  npm view @dcl/protocol dist-tags --json 2>/dev/null | sed 's/^/  /' || echo "  WARNING: npm view failed (offline?)"
else echo "WARNING: npm not available; dist-tags not shown"; fi
exit 0
