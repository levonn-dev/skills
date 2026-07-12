#!/usr/bin/env bash
# friction: SessionStart hook that injects the friction skill into context
# every session, so frictions get logged in the moment instead of only on
# the turns where the skill happens to be invoked. The SKILL.md is the
# single source of truth; this strips its YAML frontmatter and emits the
# body as context.

set -uo pipefail

SKILL="${CLAUDE_PLUGIN_ROOT}/skills/friction/SKILL.md"
[ -f "$SKILL" ] || exit 0

# Strip the leading YAML frontmatter block (--- ... ---), keep the body.
body=$(awk '
  NR==1 && $0=="---" { fm=1; next }
  fm==1 && $0=="---" { fm=0; next }
  fm!=1 { print }
' "$SKILL")

context="Friction logging is in effect for this entire session:

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
