#!/usr/bin/env bash
# docs-sync: Stop hook. When a turn ends with substantive on-disk changes
# (code or non-code) but no documentation files were touched, ask once to
# confirm or update the relevant docs before stopping.
#
# Loop-safe: exits without blocking when stop_hook_active is true, so the
#   follow-up turn this triggers is allowed to stop normally.
# Read-only: only ever runs `git rev-parse` / `git status`.
# Fails open: a missing dependency or non-repo context means no nudge, never a
#   wedged session. This is a helper, not a safety control.

set -uo pipefail

input=$(cat)

# jq is needed to read the stop flag and to emit the block decision. Without
# it, fail open.
command -v jq >/dev/null 2>&1 || exit 0

active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$active" = "true" ] && exit 0

# Pending changes, one git porcelain line per path. A test seam lets the suite
# inject fixtures without a real repo (and without running git writes);
# production reads them from git.
if [ -n "${DOCS_SYNC_TEST:-}" ]; then
  changes="${DOCS_SYNC_TEST_STATUS:-}"
else
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
  changes=$(git status --porcelain=v1 --untracked-files=all 2>/dev/null) || exit 0
fi
[ -z "$changes" ] && exit 0

# A change to any of these implies docs were already considered: suppress.
doc_re='(^|/)(README|CHANGELOG|CONTRIBUTING|AGENTS|CLAUDE|GEMINI)([.]|$)|[.](md|mdx|rst|adoc)$|(^|/)docs?/|(^|/)(openapi|swagger)|man/'

# Pure noise: never implies a doc update on its own.
ignore_re='(^|/)(package-lock[.]json|pnpm-lock[.]yaml|yarn[.]lock|go[.]sum|Cargo[.]lock|poetry[.]lock|composer[.]lock|Gemfile[.]lock)$'

doc_changed=0
substantive=0

while IFS= read -r line; do
  [ -z "$line" ] && continue
  # Strip the 2-char status field plus its trailing space.
  path="${line:3}"
  # Renames render as "old -> new"; keep the new path.
  case "$path" in
    *' -> '*) path="${path##* -> }" ;;
  esac
  # git quotes paths with special chars; drop the surrounding quotes.
  path="${path%\"}"; path="${path#\"}"
  if printf '%s' "$path" | grep -qiE "$doc_re"; then
    doc_changed=1
  elif printf '%s' "$path" | grep -qE "$ignore_re"; then
    :
  else
    substantive=1
  fi
done <<< "$changes"

[ "$substantive" -eq 1 ] && [ "$doc_changed" -eq 0 ] || exit 0

reason="Docs check before finishing: this turn changed files on disk but touched no documentation (README, docs/, *.md, CHANGELOG, API specs). Identify any docs that describe the changed behavior, config, schema, or process and update them now. This applies to non-code changes too. If nothing needs updating, say so explicitly, then stop."

jq -n --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
