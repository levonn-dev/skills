#!/usr/bin/env bash
# Sourced library: provider detection and path helpers. Defines functions only.

# True unless the value is empty, 0, or false.
delegation_truthy() {
  case "${1:-}" in
    "" | 0 | false) return 1 ;;
    *) return 0 ;;
  esac
}

# Provider by flag precedence: bedrock, vertex, foundry, anthropic-aws, mantle, gateway, anthropic.
delegation_provider() {
  if delegation_truthy "${CLAUDE_CODE_USE_BEDROCK:-}"; then echo bedrock
  elif delegation_truthy "${CLAUDE_CODE_USE_VERTEX:-}"; then echo vertex
  elif delegation_truthy "${CLAUDE_CODE_USE_FOUNDRY:-}"; then echo foundry
  elif delegation_truthy "${CLAUDE_CODE_USE_ANTHROPIC_AWS:-}"; then echo anthropic-aws
  elif delegation_truthy "${CLAUDE_CODE_USE_MANTLE:-}"; then echo bedrock
  elif [ -n "${ANTHROPIC_BASE_URL:-}" ]; then echo gateway
  else echo anthropic
  fi
}

# Config file path, overridable through DELEGATION_CONFIG.
delegation_config_path() {
  echo "${DELEGATION_CONFIG:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/delegation.json}"
}

# Log directory, overridable through DELEGATION_LOG_DIR.
delegation_log_dir() {
  echo "${DELEGATION_LOG_DIR:-${TMPDIR:-/tmp}/claude-delegation}"
}

# Where the first-run markers live: the plugin data dir, else beside the config.
delegation_marker_dir() {
  echo "${CLAUDE_PLUGIN_DATA:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/delegation}"
}

# UTC timestamp for log records.
delegation_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# Prints "<state> <config_provider>": none, malformed, ok, or mismatch; "-" when no provider is read.
delegation_config_state() {
  local path cfg
  path="$(delegation_config_path)"
  if [ ! -e "$path" ]; then
    echo "none -"
    return 0
  fi
  cfg="$(jq -r '.provider' "$path" 2>/dev/null)"
  if [ -z "$cfg" ] || [ "$cfg" = "null" ]; then
    echo "malformed -"
  elif [ "$cfg" = "$(delegation_provider)" ]; then
    echo "ok $cfg"
  else
    echo "mismatch $cfg"
  fi
}
