#!/usr/bin/env bash
# Show or set which model id each alias resolves to on this machine (ANTHROPIC_DEFAULT_<ALIAS>_MODEL in user settings).
# Usage: alias-map.sh show | set ALIAS=ID... | unset ALIAS...

set -uo pipefail

# shellcheck disable=SC1091  # path resolved at run time
source "$(dirname "$0")/settings.sh"

ALIASES=(haiku sonnet opus fable)

key_for() {
  printf 'ANTHROPIC_DEFAULT_%s_MODEL' "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
}

# The four alias keys from the settings file, as one JSON line.
four_keys() {
  delegation_settings_get '.env // {} | {ANTHROPIC_DEFAULT_HAIKU_MODEL, ANTHROPIC_DEFAULT_SONNET_MODEL, ANTHROPIC_DEFAULT_OPUS_MODEL, ANTHROPIC_DEFAULT_FABLE_MODEL}'
}

is_alias() {
  local a
  for a in "${ALIASES[@]}"; do
    [ "$a" = "$1" ] && return 0
  done
  return 1
}

# Fail unless the env block is absent or an object.
require_object_env() {
  if [ "$(delegation_settings_get '(.env // {}) | type')" != '"object"' ]; then
    echo "settings.json env is not an object; nothing written" >&2
    return 1
  fi
}

# Print the managed refusal and fail when the alias key is set in a managed file.
refuse_if_managed() {
  local alias="$1" src
  src="$(delegation_managed_source "$(key_for "$alias")" env)"
  if [ "$src" != none ]; then
    echo "$alias is managed by $src; nothing written" >&2
    return 1
  fi
}

cmd_show() {
  local alias key user src sess eligible=""
  for alias in "${ALIASES[@]}"; do
    key="$(key_for "$alias")"
    # shellcheck disable=SC2016  # $k is a jq variable
    user="$(delegation_settings_get '(.env // {}) | try .[$k] catch null | if type == "string" and . != "" then . else "unset" end' -r --arg k "$key" 2>/dev/null)"
    [ -n "$user" ] || user="unset"
    src="$(delegation_managed_source "$key" env)"
    sess="${!key-unset}"
    [ -n "$sess" ] || sess="unset"
    [ "$src" = none ] && eligible="${eligible:+$eligible }$alias"
    echo "$alias: key=$key user=$user managed=$src session=$sess"
  done
  echo "note: server-managed and MDM settings are not visible on disk; the /model picker shows what each alias resolves to"
  echo "eligible: ${eligible:-none}"
}

cmd_set() {
  local arg alias id map='{}'
  [ "$#" -gt 0 ] || { echo "usage: alias-map.sh set ALIAS=ID..." >&2; return 2; }
  for arg in "$@"; do
    case "$arg" in
      *=*) alias="${arg%%=*}"; id="${arg#*=}" ;;
      *) alias="$arg"; id="" ;;
    esac
    case "$id" in
      '' | *[[:space:]]*) echo "invalid mapping for $alias: $id" >&2; return 1 ;;
    esac
    if ! is_alias "$alias"; then
      echo "invalid mapping for $alias: $id" >&2
      return 1
    fi
    refuse_if_managed "$alias" || return 1
    map="$(printf '%s' "$map" | jq -c --arg k "$(key_for "$alias")" --arg v "$id" '. + {($k): $v}')"
  done
  delegation_settings_check || return 1
  require_object_env || return 1
  echo "before: $(four_keys)"
  # shellcheck disable=SC2016  # $m is a jq variable
  delegation_settings_merge '.env = ((.env // {}) + $m)' --argjson m "$map" || return 1
  echo "after: $(four_keys)"
}

cmd_unset() {
  local alias keys='[]'
  [ "$#" -gt 0 ] || { echo "usage: alias-map.sh unset ALIAS..." >&2; return 2; }
  for alias in "$@"; do
    if ! is_alias "$alias"; then
      echo "unknown alias: $alias" >&2
      return 1
    fi
    refuse_if_managed "$alias" || return 1
    keys="$(printf '%s' "$keys" | jq -c --arg k "$(key_for "$alias")" '. + [$k]')"
  done
  delegation_settings_check || return 1
  require_object_env || return 1
  echo "before: $(four_keys)"
  # shellcheck disable=SC2016  # $ks is a jq variable
  delegation_settings_merge 'if has("env") then .env |= del(.[$ks[]]) else . end' --argjson ks "$keys" || return 1
  echo "after: $(four_keys)"
}

case "${1:-}" in
  show) cmd_show ;;
  set) shift; cmd_set "$@" || exit $? ;;
  unset) shift; cmd_unset "$@" || exit $? ;;
  *) echo "usage: alias-map.sh show | set ALIAS=ID... | unset ALIAS..." >&2; exit 2 ;;
esac
