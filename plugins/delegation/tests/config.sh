#!/usr/bin/env bash
# Test runner for bin/config.sh and bin/cache-ttl.sh. Every path goes through
# CLAUDE_CONFIG_DIR and DELEGATION_MANAGED_DIRS pointed at temp dirs, and the
# provider is set per case under env -i.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../bin/config.sh"
TTL="$SCRIPT_DIR/../bin/cache-ttl.sh"

if [ ! -x "$CONFIG" ] || [ ! -x "$TTL" ]; then
  echo "ERROR: scripts not found or not executable: $CONFIG $TTL" >&2
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

# Fresh sandbox: sets cfg (CLAUDE_CONFIG_DIR) and managed (empty managed dir).
fresh() {
  rm -rf "$tmp/cfg" "$tmp/managed"
  mkdir -p "$tmp/cfg" "$tmp/managed"
  cfg="$tmp/cfg"
  managed="$tmp/managed"
}

# Run a script under a clean env; extra VAR=value arguments go before the script.
run() {
  env -i PATH="$PATH" HOME="$tmp/home" CLAUDE_CONFIG_DIR="$cfg" DELEGATION_MANAGED_DIRS="$managed" "$@"
}

NINE='{"version":1,"provider":"anthropic","pins":{"Explore":"haiku","general-purpose":"sonnet","delegation:explorer":"haiku","delegation:reader":"haiku","delegation:test-runner":"haiku","delegation:researcher":"sonnet","delegation:implementer":"sonnet","delegation:reviewer":"sonnet","Plan":"opus"}}'

# propose_anthropic_defaults
fresh
out="$(run "$CONFIG" propose)"
n="$(printf '%s\n' "$out" | wc -l)"
ok=0
[ "$n" = 8 ] && printf '%s\n' "$out" | grep -qxP 'Explore\thaiku\tHaiku 5\.5' \
  && printf '%s\n' "$out" | grep -qP '^delegation:reviewer\tsonnet\t' && ok=1
check propose_anthropic_defaults $ok

# propose_bedrock_annotates
fresh
out="$(run CLAUDE_CODE_USE_BEDROCK=1 "$CONFIG" propose)"
ok=0
printf '%s\n' "$out" | grep -qxP 'Explore\thaiku\tHaiku 4\.5' && ok=1
check propose_bedrock_annotates $ok

# propose_gateway_inherit
fresh
out="$(run ANTHROPIC_BASE_URL=x "$CONFIG" propose)"
ok=0
[ "$(printf '%s\n' "$out" | wc -l)" = 8 ] && [ "$(printf '%s\n' "$out" | cut -f2 | sort -u)" = inherit ] && ok=1
check propose_gateway_inherit $ok

# propose_from_existing
fresh
printf '%s\n' "$NINE" > "$cfg/delegation.json"
out="$(run "$CONFIG" propose)"
ok=0
[ "$(printf '%s\n' "$out" | wc -l)" = 9 ] && printf '%s\n' "$out" | grep -qP '^Plan\topus' && ok=1
check propose_from_existing $ok

# write_valid
fresh
run "$CONFIG" write Explore=haiku general-purpose=sonnet >/dev/null 2>&1
f="$cfg/delegation.json"
ok=0
if [ -f "$f" ] && [ "$(jq -r '.version' "$f")" = 1 ] && [ "$(jq -r '.provider' "$f")" = anthropic ] \
  && [ "$(jq -r '.pins.Explore' "$f")" = haiku ] && jq -r '.configuredAt' "$f" | grep -qE '^[0-9]{4}-'; then ok=1; fi
check write_valid $ok

# write_rejects_bad_alias
fresh
err="$(run "$CONFIG" write Explore=Haiku 2>&1 >/dev/null)"
rc=$?
ok=0
[ "$rc" = 1 ] && [[ "$err" == *"invalid alias for Explore: Haiku"* ]] && [ ! -e "$cfg/delegation.json" ] && ok=1
check write_rejects_bad_alias $ok

# write_strips_fork
fresh
err="$(run "$CONFIG" write fork=haiku Explore=haiku 2>&1 >/dev/null)"
f="$cfg/delegation.json"
ok=0
if [ "$(jq -r '.pins.fork' "$f")" = null ] && [ "$(jq -r '.pins.Explore' "$f")" = haiku ] \
  && [[ "$err" == *"fork is never pinned"* ]]; then ok=1; fi
check write_strips_fork $ok

# write_replaces_pins
fresh
printf '%s\n' "$NINE" > "$cfg/delegation.json"
run "$CONFIG" write Explore=haiku >/dev/null 2>&1
ok=0
[ "$(jq -r '.pins.Plan' "$cfg/delegation.json")" = null ] && ok=1
check write_replaces_pins $ok

# show_lists_table
fresh
out="$(run "$CONFIG" show)"
ok=0
printf '%s\n' "$out" | grep -qP '^fable\tFable 5\.1' && printf '%s\n' "$out" | grep -qx 'config: none' && ok=1
check show_lists_table $ok

# ttl_show_unset
fresh
out="$(run "$TTL" show)"
ok=0
printf '%s\n' "$out" | grep -qx 'promptCacheTtl: user=unset managed=none' \
  && printf '%s\n' "$out" | grep -qx 'eligible: yes' && ok=1
check ttl_show_unset $ok

# ttl_show_managed
fresh
printf '{"promptCacheTtl":"5m"}\n' > "$managed/managed-settings.json"
out="$(run "$TTL" show)"
ok=0
printf '%s\n' "$out" | grep -qxF "promptCacheTtl: user=unset managed=$managed/managed-settings.json" \
  && printf '%s\n' "$out" | grep -qx 'eligible: no' && ok=1
check ttl_show_managed $ok

# ttl_show_managed_dropin
fresh
mkdir -p "$managed/managed-settings.d"
printf '{"subagentPromptCacheTtl":"5m"}\n' > "$managed/managed-settings.d/x.json"
out="$(run "$TTL" show)"
ok=0
printf '%s\n' "$out" | grep -qxF "subagentPromptCacheTtl: user=unset managed=$managed/managed-settings.d/x.json" \
  && printf '%s\n' "$out" | grep -qx 'eligible: no' && ok=1
check ttl_show_managed_dropin $ok

# ttl_show_force_env
fresh
out="$(run FORCE_PROMPT_CACHING_5M=1 "$TTL" show)"
ok=0
printf '%s\n' "$out" | grep -qx 'eligible: no' && ok=1
check ttl_show_force_env $ok

# ttl_set_merges
fresh
orig='{"model":"opus","env":{"A":"1"}}'
printf '%s\n' "$orig" > "$cfg/settings.json"
run "$TTL" set 1h >/dev/null 2>&1
s="$cfg/settings.json"
ok=0
if [ "$(jq -r '.promptCacheTtl' "$s")" = 1h ] && [ "$(jq -r '.subagentPromptCacheTtl' "$s")" = 1h ] \
  && [ "$(jq -c 'del(.promptCacheTtl,.subagentPromptCacheTtl)' "$s")" = "$(jq -c . <<<"$orig")" ]; then ok=1; fi
check ttl_set_merges $ok

# ttl_set_creates
fresh
run "$TTL" set 1h >/dev/null 2>&1
s="$cfg/settings.json"
ok=0
[ -f "$s" ] && [ "$(jq -c 'keys' "$s")" = '["promptCacheTtl","subagentPromptCacheTtl"]' ] && ok=1
check ttl_set_creates $ok

# ttl_set_rejects_value
fresh
printf '{"model":"opus"}\n' > "$cfg/settings.json"
before="$(cat "$cfg/settings.json")"
run "$TTL" set 2h >/dev/null 2>&1
rc=$?
ok=0
[ "$rc" = 1 ] && [ "$(cat "$cfg/settings.json")" = "$before" ] && ok=1
check ttl_set_rejects_value $ok

# ttl_set_refuses_invalid_json
fresh
printf '{bad' > "$cfg/settings.json"
err="$(run "$TTL" set 1h 2>&1 >/dev/null)"
rc=$?
ok=0
[ "$rc" = 1 ] && [[ "$err" == *"not valid JSON"* ]] && [ "$(cat "$cfg/settings.json")" = '{bad' ] && ok=1
check ttl_set_refuses_invalid_json $ok

# write_rejects_spaced_alias
fresh
run "$CONFIG" write "Explore=sonnet haiku" >/dev/null 2>&1
rc=$?
ok=0
[ "$rc" = 1 ] && [ ! -e "$cfg/delegation.json" ] && ok=1
check write_rejects_spaced_alias $ok

# ttl_set_refuses_non_object
fresh
ok=1
for body in '[1,2]' '"x"' ''; do
  printf '%s' "$body" > "$cfg/settings.json"
  run "$TTL" set 1h >/dev/null 2>&1
  rc=$?
  { [ "$rc" = 1 ] && [ "$(cat "$cfg/settings.json")" = "$body" ]; } || ok=0
done
check ttl_set_refuses_non_object $ok

# ttl_set_refuses_multi_document
fresh
printf '{"a":1}\n{"b":2}\n' > "$cfg/settings.json"
before="$(cat "$cfg/settings.json")"
run "$TTL" set 1h >/dev/null 2>&1
rc=$?
ok=0
[ "$rc" = 1 ] && [ "$(cat "$cfg/settings.json")" = "$before" ] && ok=1
check ttl_set_refuses_multi_document $ok

# ttl_set_keeps_mode
fresh
printf '{"model":"opus"}\n' > "$cfg/settings.json"
chmod 644 "$cfg/settings.json"
run "$TTL" set 1h >/dev/null 2>&1
ok=0
[ "$(stat -c %a "$cfg/settings.json")" = 644 ] && ok=1
check ttl_set_keeps_mode $ok

# ttl_set_keeps_symlink
fresh
mkdir -p "$tmp/dotfiles"
printf '{"model":"opus"}\n' > "$tmp/dotfiles/settings.json"
ln -s "$tmp/dotfiles/settings.json" "$cfg/settings.json"
run "$TTL" set 1h >/dev/null 2>&1
ok=0
[ -L "$cfg/settings.json" ] && [ "$(jq -r '.promptCacheTtl + .subagentPromptCacheTtl' "$tmp/dotfiles/settings.json")" = 1h1h ] && ok=1
check ttl_set_keeps_symlink $ok

# bin_and_hooks_run_on_bash_3
# Stock macOS bash is 3.2: no associative arrays, mapfile, or readarray.
ok=1
grep -n -E 'declare -A|typeset -A|mapfile|readarray' "$SCRIPT_DIR"/../bin/*.sh "$SCRIPT_DIR"/../hooks/*.sh >/dev/null 2>&1 && ok=0
check bin_and_hooks_run_on_bash_3 $ok

total=$((pass + fail))
echo "Passed: $pass / $total"
if [ "$fail" -gt 0 ]; then
  printf 'FAILED: %s\n' "${failures[@]}"
  exit 1
fi
