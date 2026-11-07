#!/usr/bin/env bash
# Test runner for bin/provider.sh. Each case sources the library in a clean
# environment (env -i) with only the given variables set, and checks stdout.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../bin/provider.sh"

if [ ! -f "$LIB" ]; then
  echo "ERROR: library not found: $LIB" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
failures=()

check() {
  local name="$1" ok="$2"
  if [ "$ok" = "1" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failures+=("$name")
  fi
}

# run FUNCTION [VAR=value ...]: call a library function in a clean environment.
run() {
  local fn="$1"
  shift
  # shellcheck disable=SC2016  # the script runs in the child shell
  env -i PATH="$PATH" HOME=/h "$@" bash -c 'source "$1"; "$2"' _ "$LIB" "$fn"
}

# expect NAME EXPECTED FUNCTION [VAR=value ...]
expect() {
  local name="$1" want="$2"
  shift 2
  local got
  got="$(run "$@")"
  check "$name" "$([ "$got" = "$want" ] && echo 1 || echo 0)"
}

expect anthropic_when_unset anthropic delegation_provider
expect bedrock_flag bedrock delegation_provider CLAUDE_CODE_USE_BEDROCK=1
expect bedrock_zero_is_unset anthropic delegation_provider CLAUDE_CODE_USE_BEDROCK=0
expect bedrock_false_is_unset anthropic delegation_provider CLAUDE_CODE_USE_BEDROCK=false
expect vertex_flag vertex delegation_provider CLAUDE_CODE_USE_VERTEX=1
expect foundry_flag foundry delegation_provider CLAUDE_CODE_USE_FOUNDRY=true
expect anthropic_aws_flag anthropic-aws delegation_provider CLAUDE_CODE_USE_ANTHROPIC_AWS=1
expect mantle_is_bedrock bedrock delegation_provider CLAUDE_CODE_USE_MANTLE=1
expect base_url_is_gateway gateway delegation_provider ANTHROPIC_BASE_URL=https://proxy.example
expect bedrock_beats_base_url bedrock delegation_provider CLAUDE_CODE_USE_BEDROCK=1 ANTHROPIC_BASE_URL=x
expect config_path_default /h/.claude/delegation.json delegation_config_path
expect config_path_config_dir /c/delegation.json delegation_config_path CLAUDE_CONFIG_DIR=/c
expect config_path_seam /x.json delegation_config_path DELEGATION_CONFIG=/x.json
expect log_dir_default /tmp/claude-delegation delegation_log_dir
expect log_dir_seam /l delegation_log_dir DELEGATION_LOG_DIR=/l
expect marker_dir_default /h/.claude/delegation delegation_marker_dir
expect marker_dir_config_dir /c/delegation delegation_marker_dir CLAUDE_CONFIG_DIR=/c
expect marker_dir_plugin_data /d delegation_marker_dir CLAUDE_PLUGIN_DATA=/d

expect config_state_none "none -" delegation_config_state DELEGATION_CONFIG="$tmp/missing.json"

printf '{"provider":"anthropic"}' > "$tmp/ok.json"
expect config_state_ok "ok anthropic" delegation_config_state DELEGATION_CONFIG="$tmp/ok.json"

printf '{"provider":"bedrock"}' > "$tmp/mismatch.json"
expect config_state_mismatch "mismatch bedrock" delegation_config_state DELEGATION_CONFIG="$tmp/mismatch.json"

printf '{bad' > "$tmp/bad.json"
expect config_state_malformed "malformed -" delegation_config_state DELEGATION_CONFIG="$tmp/bad.json"

echo
echo "Passed: $pass / $((pass + fail))"
if [ "$fail" -gt 0 ]; then
  printf 'FAILED: %s\n' "${failures[@]}"
  exit 1
fi
exit 0
