#!/usr/bin/env bash
# Test runner for bin/alias-map.sh. Every path goes through CLAUDE_CONFIG_DIR
# and DELEGATION_MANAGED_DIRS pointed at temp dirs, under env -i.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAP="$SCRIPT_DIR/../bin/alias-map.sh"

if [ ! -x "$MAP" ]; then
  echo "ERROR: script not found or not executable: $MAP" >&2
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

# show_all_unset
fresh
out="$(run "$MAP" show)"
ok=0
printf '%s\n' "$out" | grep -qx 'haiku: key=ANTHROPIC_DEFAULT_HAIKU_MODEL user=unset managed=none session=unset' \
  && printf '%s\n' "$out" | grep -qx 'fable: key=ANTHROPIC_DEFAULT_FABLE_MODEL user=unset managed=none session=unset' \
  && printf '%s\n' "$out" | grep -qx 'eligible: haiku sonnet opus fable' && ok=1
check show_all_unset $ok

# show_with_empty_managed_list: an empty list means nothing is managed
fresh
out="$(env -i PATH="$PATH" HOME="$tmp/home" CLAUDE_CONFIG_DIR="$cfg" DELEGATION_MANAGED_DIRS= "$MAP" show 2>&1)"
ok=0
printf '%s\n' "$out" | grep -qx 'haiku: key=ANTHROPIC_DEFAULT_HAIKU_MODEL user=unset managed=none session=unset' && ok=1
check show_with_empty_managed_list $ok

# show_user_value
fresh
printf '{"env":{"ANTHROPIC_DEFAULT_HAIKU_MODEL":"us.anthropic.claude-haiku-4-5-20251001-v1:0"}}\n' > "$cfg/settings.json"
out="$(run "$MAP" show)"
ok=0
printf '%s\n' "$out" | grep -qx 'haiku: key=ANTHROPIC_DEFAULT_HAIKU_MODEL user=us.anthropic.claude-haiku-4-5-20251001-v1:0 managed=none session=unset' && ok=1
check show_user_value $ok

# show_managed
fresh
printf '{"env":{"ANTHROPIC_DEFAULT_OPUS_MODEL":"m"}}\n' > "$managed/managed-settings.json"
out="$(run "$MAP" show)"
ok=0
printf '%s\n' "$out" | grep -qxF "opus: key=ANTHROPIC_DEFAULT_OPUS_MODEL user=unset managed=$managed/managed-settings.json session=unset" \
  && printf '%s\n' "$out" | grep -qx 'eligible: haiku sonnet fable' && ok=1
check show_managed $ok

# show_session_value
fresh
out="$(run ANTHROPIC_DEFAULT_SONNET_MODEL=s1 "$MAP" show)"
ok=0
printf '%s\n' "$out" | grep -qx 'sonnet: key=ANTHROPIC_DEFAULT_SONNET_MODEL user=unset managed=none session=s1' && ok=1
check show_session_value $ok

# show_invalid_settings_json
fresh
printf '{bad' > "$cfg/settings.json"
out="$(run "$MAP" show)"
rc=$?
ok=0
[ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | grep -c 'user=unset')" = 4 ] \
  && printf '%s\n' "$out" | grep -qx 'eligible: haiku sonnet opus fable' && ok=1
check show_invalid_settings_json $ok

# set_merges_env
fresh
printf '{"model":"opus","env":{"A":"1"}}\n' > "$cfg/settings.json"
out="$(run "$MAP" set haiku=us.h sonnet=us.s)"
ok=0
[ "$(jq -c '{model, env}' "$cfg/settings.json")" = '{"model":"opus","env":{"A":"1","ANTHROPIC_DEFAULT_HAIKU_MODEL":"us.h","ANTHROPIC_DEFAULT_SONNET_MODEL":"us.s"}}' ] \
  && printf '%s\n' "$out" | grep -qx 'before: {"ANTHROPIC_DEFAULT_HAIKU_MODEL":null,"ANTHROPIC_DEFAULT_SONNET_MODEL":null,"ANTHROPIC_DEFAULT_OPUS_MODEL":null,"ANTHROPIC_DEFAULT_FABLE_MODEL":null}' \
  && printf '%s\n' "$out" | grep -qx 'after: {"ANTHROPIC_DEFAULT_HAIKU_MODEL":"us.h","ANTHROPIC_DEFAULT_SONNET_MODEL":"us.s","ANTHROPIC_DEFAULT_OPUS_MODEL":null,"ANTHROPIC_DEFAULT_FABLE_MODEL":null}' && ok=1
check set_merges_env $ok

# set_creates
fresh
run "$MAP" set opus=o1 >/dev/null 2>&1
ok=0
[ "$(jq -c . "$cfg/settings.json")" = '{"env":{"ANTHROPIC_DEFAULT_OPUS_MODEL":"o1"}}' ] && ok=1
check set_creates $ok

# set_accepts_equals_in_id
fresh
run "$MAP" set haiku=arn:aws:x=y >/dev/null 2>&1
ok=0
[ "$(jq -r '.env.ANTHROPIC_DEFAULT_HAIKU_MODEL' "$cfg/settings.json")" = 'arn:aws:x=y' ] && ok=1
check set_accepts_equals_in_id $ok

# set_last_wins
fresh
run "$MAP" set haiku=a haiku=b >/dev/null 2>&1
ok=0
[ "$(jq -r '.env.ANTHROPIC_DEFAULT_HAIKU_MODEL' "$cfg/settings.json")" = b ] && ok=1
check set_last_wins $ok

# set_rejects_bad_alias
fresh
err="$(run "$MAP" set Haiku=us.h 2>&1 >/dev/null)"
rc=$?
ok=0
[ "$rc" = 1 ] && [[ "$err" == *"invalid mapping for Haiku: us.h"* ]] && [ ! -e "$cfg/settings.json" ] && ok=1
check set_rejects_bad_alias $ok

# set_rejects_whitespace
fresh
run "$MAP" set "haiku=us h" >/dev/null 2>&1
rc=$?
ok=0
[ "$rc" = 1 ] && [ ! -e "$cfg/settings.json" ] && ok=1
check set_rejects_whitespace $ok

# set_rejects_missing_equals
fresh
run "$MAP" set haiku >/dev/null 2>&1
rc=$?
ok=0
[ "$rc" = 1 ] && [ ! -e "$cfg/settings.json" ] && ok=1
check set_rejects_missing_equals $ok

# set_refuses_managed
fresh
printf '{"env":{"ANTHROPIC_DEFAULT_HAIKU_MODEL":"m"}}\n' > "$managed/managed-settings.json"
err="$(run "$MAP" set sonnet=us.s haiku=us.h 2>&1 >/dev/null)"
rc=$?
ok=0
[ "$rc" = 1 ] && [[ "$err" == *"haiku is managed by $managed/managed-settings.json; nothing written"* ]] && [ ! -e "$cfg/settings.json" ] && ok=1
check set_refuses_managed $ok

# set_refuses_invalid_json
fresh
printf '{bad' > "$cfg/settings.json"
err="$(run "$MAP" set haiku=us.h 2>&1 >/dev/null)"
rc=$?
ok=0
[ "$rc" = 1 ] && [[ "$err" == *"not valid JSON"* ]] && [ "$(cat "$cfg/settings.json")" = '{bad' ] && ok=1
check set_refuses_invalid_json $ok

# set_refuses_non_object_env
fresh
printf '{"env":"x"}' > "$cfg/settings.json"
err="$(run "$MAP" set haiku=us.h 2>&1 >/dev/null)"
rc=$?
ok=0
[ "$rc" = 1 ] && [[ "$err" == *"env is not an object; nothing written"* ]] && [[ "$err" != *"jq:"* ]] && [ "$(cat "$cfg/settings.json")" = '{"env":"x"}' ] && ok=1
check set_refuses_non_object_env $ok

# unset_refuses_non_object_env
fresh
printf '{"env":"x"}' > "$cfg/settings.json"
err="$(run "$MAP" unset haiku 2>&1 >/dev/null)"
rc=$?
ok=0
[ "$rc" = 1 ] && [[ "$err" == *"env is not an object; nothing written"* ]] && [[ "$err" != *"jq:"* ]] && [ "$(cat "$cfg/settings.json")" = '{"env":"x"}' ] && ok=1
check unset_refuses_non_object_env $ok

# show_non_object_env
fresh
printf '{"env":"x"}' > "$cfg/settings.json"
err="$(run "$MAP" show 2>&1 >"$tmp/out")"
rc=$?
ok=0
[ "$rc" = 0 ] && [ -z "$err" ] && [ "$(grep -c 'user=unset' "$tmp/out")" = 4 ] && ok=1
check show_non_object_env $ok

# set_keeps_mode
fresh
printf '{}\n' > "$cfg/settings.json"
chmod 644 "$cfg/settings.json"
run "$MAP" set haiku=us.h >/dev/null 2>&1
ok=0
[ -n "$(find "$cfg/settings.json" -perm 644)" ] && ok=1
check set_keeps_mode $ok

# set_keeps_symlink
fresh
mkdir -p "$tmp/dotfiles"
printf '{}\n' > "$tmp/dotfiles/settings.json"
ln -s "$tmp/dotfiles/settings.json" "$cfg/settings.json"
run "$MAP" set haiku=us.h >/dev/null 2>&1
ok=0
[ -L "$cfg/settings.json" ] && [ "$(jq -r '.env.ANTHROPIC_DEFAULT_HAIKU_MODEL' "$tmp/dotfiles/settings.json")" = us.h ] && ok=1
check set_keeps_symlink $ok

# unset_removes_one
fresh
printf '{"env":{"ANTHROPIC_DEFAULT_HAIKU_MODEL":"h","ANTHROPIC_DEFAULT_SONNET_MODEL":"s"}}\n' > "$cfg/settings.json"
run "$MAP" unset haiku >/dev/null 2>&1
ok=0
[ "$(jq -c .env "$cfg/settings.json")" = '{"ANTHROPIC_DEFAULT_SONNET_MODEL":"s"}' ] && ok=1
check unset_removes_one $ok

# unset_missing_ok
fresh
printf '{"env":{"ANTHROPIC_DEFAULT_HAIKU_MODEL":"h"}}\n' > "$cfg/settings.json"
run "$MAP" unset opus >/dev/null 2>&1
rc=$?
ok=0
[ "$rc" = 0 ] && [ "$(jq -c .env "$cfg/settings.json")" = '{"ANTHROPIC_DEFAULT_HAIKU_MODEL":"h"}' ] && ok=1
check unset_missing_ok $ok

# unset_refuses_managed
fresh
printf '{"env":{"ANTHROPIC_DEFAULT_HAIKU_MODEL":"m"}}\n' > "$managed/managed-settings.json"
printf '{"env":{"ANTHROPIC_DEFAULT_HAIKU_MODEL":"h"}}\n' > "$cfg/settings.json"
run "$MAP" unset haiku >/dev/null 2>&1
rc=$?
ok=0
[ "$rc" = 1 ] && [ "$(jq -r '.env.ANTHROPIC_DEFAULT_HAIKU_MODEL' "$cfg/settings.json")" = h ] && ok=1
check unset_refuses_managed $ok

# unset_without_env_untouched
fresh
printf '{"model":"opus"}' > "$cfg/settings.json"
run "$MAP" unset haiku >/dev/null 2>&1
rc=$?
ok=0
[ "$rc" = 0 ] && [ "$(jq -c . "$cfg/settings.json")" = '{"model":"opus"}' ] && ok=1
check unset_without_env_untouched $ok

total=$((pass + fail))
echo "Passed: $pass / $total"
if [ "$fail" -gt 0 ]; then
  printf 'FAILED: %s\n' "${failures[@]}"
  exit 1
fi
