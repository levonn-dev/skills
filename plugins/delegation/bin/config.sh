#!/usr/bin/env bash
# Show, propose, and write the per-machine subagent model pins (delegation.json).
# Usage: config.sh show | propose | write TYPE=ALIAS...

set -uo pipefail

# shellcheck disable=SC1091  # path resolved at run time
source "$(dirname "$0")/provider.sh"

# What an alias resolves to on the given provider. Case tables, not
# associative arrays, so stock macOS bash 3.2 runs this.
resolve() {
  case "$1:$2" in
    *:inherit) echo "session model" ;;
    anthropic:haiku) echo "Haiku 5.5" ;;
    anthropic:sonnet) echo "Sonnet 5.5" ;;
    anthropic:opus) echo "Opus 5.5" ;;
    anthropic:fable) echo "Fable 5.1" ;;
    bedrock:haiku | vertex:haiku | foundry:haiku | anthropic-aws:haiku) echo "Haiku 4.5" ;;
    bedrock:sonnet | vertex:sonnet | foundry:sonnet) echo "Sonnet 4.5" ;;
    anthropic-aws:sonnet) echo "Sonnet 4.6" ;;
    bedrock:opus | vertex:opus | anthropic-aws:opus) echo "Opus 5.5" ;;
    foundry:opus) echo "Opus 4.6" ;;
    bedrock:fable | vertex:fable | foundry:fable | anthropic-aws:fable) echo "not listed" ;;
    gateway:haiku | gateway:sonnet | gateway:opus | gateway:fable) echo "decided by the gateway" ;;
    *) echo "unknown" ;;
  esac
}

# Roles in display order, and the default alias for each.
ROLES=(Explore general-purpose delegation:explorer delegation:reader delegation:test-runner delegation:researcher delegation:implementer delegation:reviewer)
default_pin() {
  case "$1" in
    Explore | delegation:explorer | delegation:reader | delegation:test-runner) echo haiku ;;
    *) echo sonnet ;;
  esac
}

cmd_show() {
  local p path a
  p="$(delegation_provider)"
  echo "provider: $p"
  for a in haiku sonnet opus fable; do
    printf '%s\t%s\n' "$a" "$(resolve "$p" "$a")"
  done
  path="$(delegation_config_path)"
  if [ -e "$path" ]; then
    cat "$path"
  else
    echo "config: none"
  fi
}

cmd_propose() {
  local p state role alias
  p="$(delegation_provider)"
  read -r state _ < <(delegation_config_state)
  if [ "$state" = ok ] || [ "$state" = mismatch ]; then
    while IFS=$'\t' read -r role alias; do
      printf '%s\t%s\t%s\n' "$role" "$alias" "$(resolve "$p" "$alias")"
    done < <(jq -r '.pins // {} | to_entries[] | "\(.key)\t\(.value)"' "$(delegation_config_path)")
    return 0
  fi
  for role in "${ROLES[@]}"; do
    alias="$(default_pin "$role")"
    [ "$p" = gateway ] && alias=inherit
    printf '%s\t%s\t%s\n' "$role" "$alias" "$(resolve "$p" "$alias")"
  done
}

cmd_write() {
  local pair type alias path dir tmp pins='{}'
  local -a types=() aliases=()
  for pair in "$@"; do
    type="${pair%%=*}"
    alias="${pair#*=}"
    if [ "$type" = fork ]; then
      echo "fork is never pinned; dropped" >&2
      continue
    fi
    if [ "$type" = "$pair" ] || [ -z "$type" ]; then
      echo "invalid alias for $type: $alias" >&2
      return 1
    fi
    case "$alias" in
      opus | sonnet | haiku | fable | inherit) ;;
      *) echo "invalid alias for $type: $alias" >&2; return 1 ;;
    esac
    types+=("$type")
    aliases+=("$alias")
  done
  for i in "${!types[@]}"; do
    pins="$(jq -c --arg k "${types[$i]}" --arg v "${aliases[$i]}" '. + {($k): $v}' <<<"$pins")"
  done
  path="$(delegation_config_path)"
  dir="$(dirname "$path")"
  mkdir -p "$dir"
  tmp="$(mktemp "$dir/.delegation.XXXXXX")"
  if ! { jq -n --arg provider "$(delegation_provider)" --arg now "$(delegation_now)" --argjson pins "$pins" \
    '{version: 1, provider: $provider, configuredAt: $now, pins: $pins}' >"$tmp" && mv "$tmp" "$path"; }; then
    rm -f "$tmp"
    echo "could not write $path; nothing written" >&2
    return 1
  fi
  cat "$path"
}

case "${1:-}" in
  show) cmd_show ;;
  propose) cmd_propose ;;
  write) shift; cmd_write "$@" ;;
  *) echo "usage: config.sh show | propose | write TYPE=ALIAS..." >&2; exit 2 ;;
esac
