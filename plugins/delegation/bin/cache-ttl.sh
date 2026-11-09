#!/usr/bin/env bash
# Show or set the prompt cache lifetime keys in user settings.
# Usage: cache-ttl.sh show | set 5m|1h

set -uo pipefail

# shellcheck disable=SC1091  # path resolved at run time
source "$(dirname "$0")/settings.sh"

KEYS=(promptCacheTtl subagentPromptCacheTtl)
SETTINGS="$(delegation_settings_path)"

# The two keys from the settings file, as one JSON line.
two_keys() {
  delegation_settings_get '{promptCacheTtl, subagentPromptCacheTtl}'
}

cmd_show() {
  local key user src eligible=yes
  for key in "${KEYS[@]}"; do
    user="unset"
    if [ -f "$SETTINGS" ]; then
      user="$(jq -r --arg k "$key" '.[$k] // "unset"' "$SETTINGS" 2>/dev/null || echo unset)"
    fi
    src="$(delegation_managed_source "$key")"
    [ "$src" = none ] || eligible=no
    echo "$key: user=$user managed=$src"
  done
  echo "env: FORCE_PROMPT_CACHING_5M=${FORCE_PROMPT_CACHING_5M-unset} CLAUDE_CODE_PROMPT_CACHE_TTL=${CLAUDE_CODE_PROMPT_CACHE_TTL-unset} CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL=${CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL-unset}"
  echo "note: server-managed and MDM settings are not visible on disk; a value with no effect in /usage is managed"
  [ -z "${FORCE_PROMPT_CACHING_5M:-}" ] || eligible=no
  echo "eligible: $eligible"
}

cmd_set() {
  local value="${1:-}"
  case "$value" in
    5m | 1h) ;;
    *) echo "usage: cache-ttl.sh set 5m|1h" >&2; return 1 ;;
  esac
  delegation_settings_check || return 1
  echo "before: $(two_keys)"
  # shellcheck disable=SC2016  # $v is a jq variable
  delegation_settings_merge '. + {promptCacheTtl: $v, subagentPromptCacheTtl: $v}' --arg v "$value" || return 1
  echo "after: $(two_keys)"
}

case "${1:-}" in
  show) cmd_show ;;
  set) shift; cmd_set "$@" ;;
  *) echo "usage: cache-ttl.sh show | set 5m|1h" >&2; exit 2 ;;
esac
