#!/usr/bin/env bash
# Show or set the prompt cache lifetime keys in user settings.
# Usage: cache-ttl.sh show | set 5m|1h

set -uo pipefail

KEYS=(promptCacheTtl subagentPromptCacheTtl)
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
DEFAULT_MANAGED="/etc/claude-code:/Library/Application Support/ClaudeCode:/mnt/c/Program Files/ClaudeCode:/c/Program Files/ClaudeCode"

# First managed file that sets the key, or "none".
managed_source() {
  local key="$1" dir f
  local -a dirs
  IFS=: read -ra dirs <<<"${DELEGATION_MANAGED_DIRS-$DEFAULT_MANAGED}"
  for dir in "${dirs[@]}"; do
    [ -n "$dir" ] || continue
    for f in "$dir/managed-settings.json" "$dir"/managed-settings.d/*.json; do
      [ -f "$f" ] || continue
      if jq -e --arg k "$key" 'has($k)' "$f" >/dev/null 2>&1; then
        echo "$f"
        return 0
      fi
    done
  done
  echo none
}

# The two keys from the settings file, as one JSON line.
two_keys() {
  jq -c '{promptCacheTtl, subagentPromptCacheTtl}' "$SETTINGS"
}

cmd_show() {
  local key user src eligible=yes
  for key in "${KEYS[@]}"; do
    user="unset"
    if [ -f "$SETTINGS" ]; then
      user="$(jq -r --arg k "$key" '.[$k] // "unset"' "$SETTINGS" 2>/dev/null || echo unset)"
    fi
    src="$(managed_source "$key")"
    [ "$src" = none ] || eligible=no
    echo "$key: user=$user managed=$src"
  done
  echo "env: FORCE_PROMPT_CACHING_5M=${FORCE_PROMPT_CACHING_5M-unset} CLAUDE_CODE_PROMPT_CACHE_TTL=${CLAUDE_CODE_PROMPT_CACHE_TTL-unset} CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL=${CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL-unset}"
  echo "note: server-managed and MDM settings are not visible on disk; a value with no effect in /usage is managed"
  [ -z "${FORCE_PROMPT_CACHING_5M:-}" ] || eligible=no
  echo "eligible: $eligible"
}

cmd_set() {
  local value="${1:-}" tmp target
  case "$value" in
    5m | 1h) ;;
    *) echo "usage: cache-ttl.sh set 5m|1h" >&2; return 1 ;;
  esac
  # Exactly one JSON object, or refuse.
  if [ -f "$SETTINGS" ] && ! { jq -e 'type == "object"' "$SETTINGS" >/dev/null 2>&1 && [ "$(jq -s 'length' "$SETTINGS" 2>/dev/null)" = 1 ]; }; then
    echo "settings.json is not valid JSON; nothing written" >&2
    return 1
  fi
  mkdir -p "$(dirname "$SETTINGS")"
  [ -f "$SETTINGS" ] || echo '{}' >"$SETTINGS"
  # Replace the real file, not a symlink to it, and keep its mode.
  target="$(readlink -f "$SETTINGS" 2>/dev/null)"
  [ -n "$target" ] || target="$SETTINGS"
  echo "before: $(two_keys)"
  tmp="$(mktemp "$(dirname "$target")/.settings.XXXXXX")" || { echo "settings.json could not be written; nothing written" >&2; return 1; }
  # cp -p copies the mode portably; jq then truncates and fills the copy.
  if ! cp -p "$target" "$tmp"; then
    rm -f "$tmp"
    echo "settings.json could not be written; nothing written" >&2
    return 1
  fi
  if ! { jq --arg v "$value" '. + {promptCacheTtl: $v, subagentPromptCacheTtl: $v}' "$SETTINGS" >"$tmp" && mv "$tmp" "$target"; }; then
    rm -f "$tmp"
    echo "settings.json could not be written; nothing written" >&2
    return 1
  fi
  echo "after: $(two_keys)"
}

case "${1:-}" in
  show) cmd_show ;;
  set) shift; cmd_set "$@" ;;
  *) echo "usage: cache-ttl.sh show | set 5m|1h" >&2; exit 2 ;;
esac
