#!/usr/bin/env bash
# coding-guidelines: SessionStart hook that injects the guidelines into context
# every session, so they apply unconditionally instead of only on the turns
# where the skill happens to be invoked. The SKILL.md is the single source of
# truth; this strips its YAML frontmatter and emits the body as context.

set -uo pipefail

SKILL="${CLAUDE_PLUGIN_ROOT}/skills/coding-guidelines/SKILL.md"
[ -f "$SKILL" ] || exit 0

# Strip the leading YAML frontmatter block (--- ... ---), keep the body.
body=$(awk '
  NR==1 && $0=="---" { fm=1; next }
  fm==1 && $0=="---" { fm=0; next }
  fm!=1 { print }
' "$SKILL")

context="These coding guidelines are in effect for this entire session. Apply them whenever you write, review, or refactor code:

${body}"

# Preferred contract: JSON additionalContext. Falls back to plain stdout, which
# SessionStart also adds to context, if jq is unavailable.
if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$context" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
else
  printf '%s\n' "$context"
fi

exit 0
