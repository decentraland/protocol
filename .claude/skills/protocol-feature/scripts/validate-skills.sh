#!/usr/bin/env bash
# validate-skills.sh - structural checks for every .claude/skills/*/SKILL.md in this repo.
#
# Usage: validate-skills.sh [--root <repo root>]
#
# Per skill: frontmatter present; name <= 64 chars matching ^[a-z0-9-]+$ (warns when it differs from
# the directory name); description non-empty and <= 1024 chars; body < 500 lines; every relative
# markdown link and every backticked relative path (references/, assets/, examples/, evals/, scripts/*.sh,
# .claude/skills/...) mentioned in any .md under the skill resolves to an existing file (relative to the
# .md, the skill dir, or the repo root); a .claude/skills/<other> path for a skill not in this repo is a WARNING; files over 100
# lines under references/ start with a "## Contents" TOC (within the first 12 lines); every file under
# scripts/ is executable; no hard-coded home-directory paths (a macOS user-home prefix or a tilde Projects
# path) in any skill file.
# Then it sums the description lengths of the skills WITHOUT `disable-model-invocation: true` (the
# text Claude sees in its skill listing) against ~8000 chars (1% of a 200k context) and the 1536-char
# per-entry cap. Exit 1 on any violation (all are listed), 0 when clean.
set -u

usage() { awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; }
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
ROOT=""
while [ $# -gt 0 ]; do case "$1" in --root) shift; ROOT=${1:-} ;; -h|--help) usage; exit 0 ;; *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;; esac; shift; done
if [ -z "$ROOT" ]; then
  ROOT=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)
  [ -n "$ROOT" ] && [ -d "$ROOT/.claude/skills" ] || ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)
fi
[ -n "$ROOT" ] && [ -d "$ROOT/.claude/skills" ] || { echo "ERROR: no .claude/skills under ${ROOT:-cwd}" >&2; exit 2; }
SKILLS="$ROOT/.claude/skills"

# the forbidden literals are assembled so this file itself does not contain them
HOMEPAT="/Use""rs/"; TILDEPAT="~/Proj""ects"

VIOL=0; WARN=0
viol() { echo "VIOLATION: $1"; VIOL=$((VIOL+1)); }
warn() { echo "WARNING: $1"; WARN=$((WARN+1)); }

TOTAL_DESC=0; TOTAL_LISTED=0; NSKILLS=0
for skill_md in "$SKILLS"/*/SKILL.md; do
  [ -f "$skill_md" ] || continue
  NSKILLS=$((NSKILLS+1))
  sdir=$(dirname "$skill_md"); sname=$(basename "$sdir"); rel=".claude/skills/$sname"
  echo "== $rel/SKILL.md"
  # frontmatter
  if [ "$(head -1 "$skill_md" | tr -d '\r')" != "---" ] || ! awk 'NR>1 && /^---[ \t\r]*$/ { f=1; exit } END { exit f?0:1 }' "$skill_md"; then
    viol "$rel/SKILL.md: no YAML frontmatter block"; continue
  fi
  fm=$(awk 'NR==1 { next } /^---[ \t\r]*$/ { exit } { print }' "$skill_md")
  body_lines=$(awk 'NR==1 { next } found { n++; next } /^---[ \t\r]*$/ { found=1 } END { print n+0 }' "$skill_md")
  name=$(printf '%s\n' "$fm" | awk 'index($0,"name:")==1 { v=substr($0,6); gsub(/^[ \t]+|[ \t\r]+$/, "", v); gsub(/^["'"'"']|["'"'"']$/, "", v); print v; exit }')
  # description: single line, quoted, or block scalar (>, |) continued by indented lines
  desc=$(printf '%s\n' "$fm" | awk '
    index($0,"description:")==1 { v=substr($0,13); gsub(/^[ \t]+|[ \t\r]+$/, "", v)
      if (v ~ /^[>|][-+]?$/) { blk=1; next } gsub(/^["'"'"']|["'"'"']$/, "", v); out=v; blk=0; done=1; next }
    blk && /^[ \t]+/ { l=$0; gsub(/^[ \t]+|[ \t\r]+$/, "", l); out = out (out==""?"":" ") l; next }
    blk { blk=0; done=1 }
    END { print out }')
  dmi=$(printf '%s\n' "$fm" | grep -c -E '^disable-model-invocation:[[:space:]]*true[[:space:]]*$')
  nlen=${#name}; dlen=${#desc}
  echo "   name=$name (${nlen} chars)  description=${dlen} chars  body=${body_lines} lines  disable-model-invocation=$([ "$dmi" -gt 0 ] && echo true || echo false)"
  [ -n "$name" ] || viol "$rel: frontmatter 'name' missing"
  [ "$nlen" -le 64 ] || viol "$rel: name is $nlen chars (max 64)"
  printf '%s' "$name" | grep -q -E '^[a-z0-9-]+$' || viol "$rel: name '$name' must match ^[a-z0-9-]+\$"
  [ "$name" = "$sname" ] || warn "$rel: name '$name' differs from directory '$sname'"
  [ "$dlen" -gt 0 ] || viol "$rel: description is empty"
  [ "$dlen" -le 1024 ] || viol "$rel: description is $dlen chars (max 1024)"
  [ "$body_lines" -lt 500 ] || viol "$rel/SKILL.md: body is $body_lines lines (must be < 500)"
  TOTAL_DESC=$((TOTAL_DESC + dlen))
  if [ "$dmi" -eq 0 ]; then
    TOTAL_LISTED=$((TOTAL_LISTED + dlen))
    [ "$dlen" -le 1536 ] || viol "$rel: model-visible description is $dlen chars (listing entry cap 1536)"
  fi

  # relative links/paths in every .md under the skill
  find "$sdir" -type f -name '*.md' | sort | while IFS= read -r md; do
    mrel=${md#$ROOT/}; mdir=$(dirname "$md")
    { grep -o -E '\]\([^)]+\)' "$md" | sed -E 's/^\]\(//; s/\)$//' | sed -E 's/[[:space:]]+"[^"]*"$//'
      grep -o -E "\`[^\`]+\`" "$md" | tr -d "\`" | grep -E "^(\.\./)?((references|assets|examples|evals|\.claude/skills)/[A-Za-z0-9_./-]+|scripts/[A-Za-z0-9_.-]+\.sh)$"; } \
      | sort -u | while IFS= read -r link; do
        [ -n "$link" ] || continue
        case "$link" in http://*|https://*|mailto:*|\#*|/*) continue ;; esac
        case "$link" in *"<"*|*"*"*|*"{"*|*"$"*) continue ;; esac   # placeholders and globs
        target=${link%%#*}; [ -n "$target" ] || continue
        ok=0; for base in "$mdir" "$sdir" "$ROOT"; do [ -e "$base/$target" ] && { ok=1; break; }; done
        [ "$ok" = 1 ] && continue
        case "$target" in
          .claude/skills/*) other=${target#.claude/skills/}; other=${other%%/*}
            if [ -d "$SKILLS/$other" ]; then echo "VIOLATION: $mrel references '$link' which does not exist"; else echo "WARNING: $mrel references '$link', a skill not in this repo (fine if it lives in unity-explorer/godot-explorer; say which repo)"; fi ;;
          *) echo "VIOLATION: $mrel references '$link' which does not exist (tried relative to the file, the skill dir and the repo root)" ;;
        esac
      done
  done > "$sdir/.validate-links.$$" 2>/dev/null
  if [ -s "$sdir/.validate-links.$$" ]; then cat "$sdir/.validate-links.$$"; VIOL=$((VIOL + $(grep -c "^VIOLATION" "$sdir/.validate-links.$$"))); WARN=$((WARN + $(grep -c "^WARNING" "$sdir/.validate-links.$$"))); fi
  rm -f "$sdir/.validate-links.$$"

  # references/ files > 100 lines start with a ## Contents TOC
  if [ -d "$sdir/references" ]; then
    find "$sdir/references" -type f -name '*.md' | sort | while IFS= read -r rf; do
      n=$(wc -l < "$rf" | tr -d ' ')
      if [ "$n" -gt 100 ] && ! head -12 "$rf" | grep -q -E '^## Contents'; then echo "VIOLATION: ${rf#$ROOT/} has $n lines but no '## Contents' TOC in its first 12 lines"; fi
    done > "$sdir/.validate-toc.$$"
    if [ -s "$sdir/.validate-toc.$$" ]; then cat "$sdir/.validate-toc.$$"; VIOL=$((VIOL + $(grep -c . "$sdir/.validate-toc.$$"))); fi
    rm -f "$sdir/.validate-toc.$$"
  fi

  # scripts executable
  if [ -d "$sdir/scripts" ]; then
    for sc in "$sdir"/scripts/*; do
      [ -f "$sc" ] || continue
      [ -x "$sc" ] || viol "${sc#$ROOT/} is not executable (chmod +x)"
      case "$sc" in *.sh) head -1 "$sc" | grep -q -E '^#!/usr/bin/env bash|^#!/bin/bash' || warn "${sc#$ROOT/} has no bash shebang" ;; esac
    done
  fi

  # literal home paths anywhere under the skill
  hits=$(grep -r -n -F -e "$HOMEPAT" -e "$TILDEPAT" "$sdir" 2>/dev/null | grep -v '\.validate-' | head -20)
  if [ -n "$hits" ]; then printf '%s\n' "$hits" | sed "s|^$ROOT/||" | while IFS= read -r h; do echo "VIOLATION: literal home path: $h"; done; VIOL=$((VIOL + $(printf '%s\n' "$hits" | grep -c .))); fi
done

[ "$NSKILLS" -gt 0 ] || { echo "ERROR: no .claude/skills/*/SKILL.md under $ROOT" >&2; exit 2; }
echo
echo "description budget: $NSKILLS skills; model-visible descriptions (no disable-model-invocation) total $TOTAL_LISTED chars (all skills: $TOTAL_DESC); budget ~8000 chars (1% of 200k context); per-entry cap 1536"
[ "$TOTAL_LISTED" -le 8000 ] || viol "model-visible descriptions total $TOTAL_LISTED chars > 8000 budget"
echo
if [ "$VIOL" -gt 0 ]; then echo "RESULT: $VIOL violation(s), $WARN warning(s)"; exit 1; fi
echo "RESULT: OK ($WARN warning(s))"
exit 0
