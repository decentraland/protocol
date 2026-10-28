#!/usr/bin/env bash
# find-repos.sh - locate the Decentraland repos the protocol-feature skill works across.
#
# Read-only, except that --fetch (default OFF) runs `git fetch origin --prune -q` in every
# repo it finds. It never checks out, commits, or touches files. Always exits 0 (safe for
# command injection in skill prompts), except `--path` (1 when the repo is missing) and
# usage errors (2).
#
# Usage:
#   find-repos.sh [--fetch] [--json|--tsv] [--quiet] [--only <repo,...>]
#   find-repos.sh --path <repo>            # print the primary path only (exit 1 if missing)
#
# Repos: protocol js-sdk-toolchain unity-explorer bevy-explorer godot-explorer
#        sdk7-test-scenes docs adr sdk-skills scene-explorer-tests
#
# Search order for <repo>:
#   1. $DCL_REPOS_ROOT/<repo>
#   2. ../<repo>  (sibling of the protocol clone)
#   3. $HOME/Projects/decentraland/<repo>
#   4. $HOME/orca/<repo>
# A directory is accepted only when `git -C <dir> remote get-url origin` matches
# decentraland/<repo> (ssh or https). protocol = the clone containing the current
# directory (fallback: the clone containing this script); every other protocol clone
# found by the search is reported too, so stale second clones are visible.
#
# Per repo it prints: name, path, branch, HEAD sha, origin default-branch sha (`dev` for
# unity-explorer), commits behind that branch, dirty file count, FETCH_HEAD age in hours,
# or `MISSING -> gh repo clone decentraland/<repo>`. WARNING lines go to stdout when a
# repo is missing or its FETCH_HEAD is older than 24h (suppressed by --quiet).
#
# --json prints {"repos":[{...}],"warnings":["..."]}. --tsv prints one row per repo:
#   name  path  branch  head  default_branch  default_sha  behind  dirty  fetch_age_h  status
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
ALL_REPOS="protocol js-sdk-toolchain unity-explorer bevy-explorer godot-explorer sdk7-test-scenes docs adr sdk-skills scene-explorer-tests"

usage() { awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; }

DO_FETCH=0; MODE=human; QUIET=0; ONLY=""; PATH_ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fetch) DO_FETCH=1 ;;
    --json) MODE=json ;;
    --tsv) MODE=tsv ;;
    --quiet|-q) QUIET=1 ;;
    --only) shift; ONLY=${1:-} ;;
    --path) shift; PATH_ONLY=${1:-}; QUIET=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

remote_matches() { # <dir> <repo>  -> 0 when origin points at decentraland/<repo>
  local url
  url=$(git -C "$1" remote get-url origin 2>/dev/null) || return 1
  case "$url" in
    *github.com:decentraland/"$2".git|*github.com:decentraland/"$2"|*github.com/decentraland/"$2".git|*github.com/decentraland/"$2"|*github.com/decentraland/"$2"/) return 0 ;;
  esac
  return 1
}

physical() { ( cd "$1" 2>/dev/null && pwd -P ); }

toplevel_of() { git -C "$1" rev-parse --show-toplevel 2>/dev/null; }

# --- primary protocol clone: the one containing cwd, else the one containing this script
PROTOCOL_DIR=""
t=$(toplevel_of "$PWD")
if [ -n "$t" ] && remote_matches "$t" protocol; then PROTOCOL_DIR=$(physical "$t"); fi
if [ -z "$PROTOCOL_DIR" ]; then
  t=$(toplevel_of "$SCRIPT_DIR")
  if [ -n "$t" ] && remote_matches "$t" protocol; then PROTOCOL_DIR=$(physical "$t"); fi
fi

candidates() { # <repo> -> candidate dirs, one per line, search order
  [ -n "${DCL_REPOS_ROOT:-}" ] && echo "$DCL_REPOS_ROOT/$1"
  [ -n "$PROTOCOL_DIR" ] && echo "$(dirname "$PROTOCOL_DIR")/$1"
  echo "$HOME/Projects/decentraland/$1"
  echo "$HOME/orca/$1"
}

# all_matches <repo> -> every distinct accepted dir, search order (protocol: primary first)
all_matches() {
  local repo=$1 seen="" c p
  if [ "$repo" = protocol ] && [ -n "$PROTOCOL_DIR" ]; then echo "$PROTOCOL_DIR"; seen="|$PROTOCOL_DIR|"; fi
  candidates "$repo" | while read -r c; do
    [ -d "$c/.git" ] || [ -f "$c/.git" ] || continue
    p=$(physical "$c"); [ -n "$p" ] || continue
    case "$seen" in *"|$p|"*) continue ;; esac
    seen="$seen|$p|"
    remote_matches "$p" "$repo" && echo "$p"
  done
}

default_branch() { # <dir> <repo>
  local ref
  ref=$(git -C "$1" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
  if [ -n "$ref" ]; then echo "${ref#origin/}"; return; fi
  case "$2" in unity-explorer) echo dev ;; *) echo main ;; esac
}

fetch_age_hours() { # <dir> -> hours since FETCH_HEAD was written, or "never"
  local gp f m now
  gp=$(git -C "$1" rev-parse --git-path FETCH_HEAD 2>/dev/null) || { echo never; return; }
  case "$gp" in /*) f=$gp ;; *) f="$1/$gp" ;; esac
  [ -f "$f" ] || { echo never; return; }
  m=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null) || { echo never; return; }
  now=$(date +%s)
  echo $(( (now - m) / 3600 ))
}

# --- --path mode: lookup only, no stats
if [ -n "$PATH_ONLY" ]; then
  p=$(all_matches "$PATH_ONLY" | head -1)
  if [ -n "$p" ]; then echo "$p"; exit 0; fi
  exit 1
fi

WARNINGS=""
warn() { WARNINGS="$WARNINGS$1"$'\n'; [ "$QUIET" = 1 ] || [ "$MODE" != human ] || echo "WARNING: $1"; }

ROWS=""   # tab-separated rows, newline-terminated
add_row() { ROWS="$ROWS$1"$'\n'; }

selected() { # <repo> -> 0 when in --only (or no --only)
  [ -z "$ONLY" ] && return 0
  case ",$ONLY," in *",$1,"*) return 0 ;; esac
  return 1
}

for repo in $ALL_REPOS; do
  selected "$repo" || continue
  found=0
  for d in $(all_matches "$repo"); do
    found=1
    if [ "$DO_FETCH" = 1 ]; then
      git -C "$d" fetch origin --prune -q 2>/dev/null || warn "$repo: git fetch failed (offline?) at $d"
    fi
    branch=$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
    head=$(git -C "$d" rev-parse --short HEAD 2>/dev/null || echo "?")
    def=$(default_branch "$d" "$repo")
    def_sha=$(git -C "$d" rev-parse --short "origin/$def" 2>/dev/null || echo "?")
    behind=$(git -C "$d" rev-list --count "HEAD..origin/$def" 2>/dev/null || echo "?")
    dirty=$(git -C "$d" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    age=$(fetch_age_hours "$d")
    if [ "$age" = never ]; then warn "$repo: never fetched (no FETCH_HEAD) at $d; run: git -C $d fetch origin --prune"
    elif [ "$age" -gt 24 ]; then warn "$repo: FETCH_HEAD is ${age}h old at $d; origin/* may be stale (run find-repos.sh --fetch)"; fi
    add_row "$repo	$d	$branch	$head	$def	$def_sha	$behind	$dirty	$age	ok"
    # only the first protocol clone is "the" protocol; extra clones are reported as extra
    [ "$repo" = protocol ] || break
  done
  if [ "$found" = 0 ]; then
    warn "$repo: MISSING (searched \$DCL_REPOS_ROOT, ../$repo, \$HOME/Projects/decentraland/$repo, \$HOME/orca/$repo); clone with: gh repo clone decentraland/$repo"
    add_row "$repo	-	-	-	-	-	-	-	-	MISSING"
  fi
done

case "$MODE" in
  tsv)
    printf '%s' "$ROWS"
    ;;
  json)
    printf '{"repos":['
    first=1
    printf '%s' "$ROWS" | while IFS='	' read -r name path branch head def def_sha behind dirty age status; do
      [ -n "$name" ] || continue
      if [ "$first" = 1 ]; then first=0; else printf ','; fi
      printf '{"name":"%s","path":"%s","branch":"%s","head":"%s","default_branch":"%s","default_sha":"%s","behind":"%s","dirty":"%s","fetch_age_hours":"%s","status":"%s"' \
        "$name" "$path" "$branch" "$head" "$def" "$def_sha" "$behind" "$dirty" "$age" "$status"
      if [ "$status" = MISSING ]; then printf ',"clone":"gh repo clone decentraland/%s"' "$name"; fi
      printf '}'
      first=0
    done
    printf '],"warnings":['
    first=1
    printf '%s' "$WARNINGS" | while IFS= read -r w; do
      [ -n "$w" ] || continue
      if [ "$first" = 1 ]; then first=0; else printf ','; fi
      printf '"%s"' "$(printf '%s' "$w" | sed 's/\\/\\\\/g; s/"/\\"/g')"
      first=0
    done
    printf ']}\n'
    ;;
  *)
    seen_protocol=0
    printf '%s' "$ROWS" | while IFS='	' read -r name path branch head def def_sha behind dirty age status; do
      [ -n "$name" ] || continue
      if [ "$status" = MISSING ]; then
        printf '%-20s MISSING -> gh repo clone decentraland/%s\n' "$name" "$name"
        continue
      fi
      label=$name
      if [ "$name" = protocol ]; then
        if [ "$seen_protocol" = 1 ]; then label="protocol(extra)"; fi
        seen_protocol=1
      fi
      printf '%-20s %s  branch=%s  head=%s  origin/%s=%s  behind=%s  dirty=%s  fetched=%sh ago\n' \
        "$label" "$path" "$branch" "$head" "$def" "$def_sha" "$behind" "$dirty" "$age"
    done
    [ "$DO_FETCH" = 1 ] || [ "$QUIET" = 1 ] || echo "note: origin/* refs are as last fetched; pass --fetch to run 'git fetch origin --prune' in each repo"
    ;;
esac
exit 0
