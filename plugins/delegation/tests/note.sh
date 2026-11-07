#!/usr/bin/env bash
# Test runner for session-note.sh.
# Each case runs the hook in a clean environment and parses the JSON it prints.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/session-note.sh"
HOOKS_JSON="$SCRIPT_DIR/../hooks/hooks.json"

if [ ! -f "$HOOK" ]; then
  echo "ERROR: hook not found: $HOOK" >&2
  exit 1
fi

pass=0
fail=0
total=0
failures=()
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# check NAME OK [DETAIL]: tally one case.
check() {
  total=$((total + 1))
  if [ "$2" = 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failures+=("$1${3:+: $3}")
  fi
}

# run_note CFG [VAR=VALUE...]: print the additionalContext the hook emits.
run_note() {
  local cfg="$1"
  shift
  echo '{}' | env -i PATH="$PATH" HOME="$tmp" DELEGATION_CONFIG="$cfg" "$@" bash "$HOOK" \
    | jq -r '.hookSpecificOutput.additionalContext'
}

# run_hook CFG SOURCE [VAR=VALUE...]: print the raw JSON the hook emits for a
# SessionStart payload with the given source.
run_hook() {
  local cfg="$1" source="$2"
  shift 2
  printf '{"session_id":"s1","hook_event_name":"SessionStart","source":"%s"}' "$source" \
    | env -i PATH="$PATH" HOME="$tmp" DELEGATION_CONFIG="$cfg" "$@" bash "$HOOK"
}

# has TEXT NEEDLE: 1 when TEXT contains NEEDLE.
has() {
  case "$1" in *"$2"*) echo 1 ;; *) echo 0 ;; esac
}

# note_defaults
ctx="$(run_note "$tmp/absent.json")"
ok=0
[ "$(has "$ctx" 'This machine is on defaults')" = 1 ] \
  && [ "$(has "$ctx" '/delegation:report')" = 1 ] \
  && [ "${#ctx}" -lt 650 ] && ok=1
check note_defaults "$ok" "len ${#ctx}"

# note_configured
echo '{"provider":"anthropic"}' > "$tmp/ok.json"
ctx="$(run_note "$tmp/ok.json")"
check note_configured "$(has "$ctx" 'Pins for anthropic are configured.')"

# note_mismatch_longest
echo '{"provider":"anthropic-aws"}' > "$tmp/mm.json"
ctx="$(run_note "$tmp/mm.json" CLAUDE_CODE_USE_FOUNDRY=1)"
ok=0
[ "$(has "$ctx" 'made for anthropic-aws, this session is on foundry')" = 1 ] \
  && [ "${#ctx}" -lt 650 ] && ok=1
check note_mismatch_longest "$ok" "len ${#ctx}"

# note_malformed
echo '{bad' > "$tmp/bad.json"
ctx="$(run_note "$tmp/bad.json")"
check note_malformed "$(has "$ctx" 'did not parse')"

# first_run_message_on_startup
rm -rf "$tmp/data"
out="$(run_hook "$tmp/absent.json" startup CLAUDE_PLUGIN_DATA="$tmp/data")"
ok=0
[ "$(has "$(jq -r '.systemMessage // empty' <<<"$out")" '/delegation:configure')" = 1 ] \
  && [ "$(has "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")" 'This machine is on defaults')" = 1 ] \
  && [ -f "$tmp/data/configure-offered.anthropic" ] && ok=1
check first_run_message_on_startup "$ok" "$out"

# first_run_message_once
out="$(run_hook "$tmp/absent.json" startup CLAUDE_PLUGIN_DATA="$tmp/data")"
check first_run_message_once "$([ "$(jq -r '.systemMessage // empty' <<<"$out")" = "" ] && echo 1 || echo 0)" "$out"

# first_run_not_on_resume
rm -rf "$tmp/data"
ok=1
for src in resume clear compact fork; do
  out="$(run_hook "$tmp/absent.json" "$src" CLAUDE_PLUGIN_DATA="$tmp/data")"
  { [ "$(jq -r '.systemMessage // empty' <<<"$out")" = "" ] && [ ! -e "$tmp/data" ]; } || ok=0
done
check first_run_not_on_resume "$ok"

# first_run_silent_with_config
rm -rf "$tmp/data"
out="$(run_hook "$tmp/ok.json" startup CLAUDE_PLUGIN_DATA="$tmp/data")"
ok=0
[ "$(jq -r '.systemMessage // empty' <<<"$out")" = "" ] && [ ! -e "$tmp/data" ] && ok=1
check first_run_silent_with_config "$ok" "$out"

# first_run_per_provider
rm -rf "$tmp/data"
mkdir -p "$tmp/data" && : > "$tmp/data/configure-offered.anthropic"
out="$(run_hook "$tmp/absent.json" startup CLAUDE_PLUGIN_DATA="$tmp/data" CLAUDE_CODE_USE_BEDROCK=1)"
ok=0
[ -n "$(jq -r '.systemMessage // empty' <<<"$out")" ] && [ -f "$tmp/data/configure-offered.bedrock" ] && ok=1
check first_run_per_provider "$ok" "$out"

# first_run_silent_when_unwritable
: > "$tmp/notadir"
out="$(run_hook "$tmp/absent.json" startup CLAUDE_PLUGIN_DATA="$tmp/notadir/data")"
rc=$?
ok=0
[ "$rc" = 0 ] && [ "$(jq -r '.systemMessage // empty' <<<"$out")" = "" ] \
  && [ "$(has "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")" 'on defaults')" = 1 ] && ok=1
check first_run_silent_when_unwritable "$ok" "$out"

# first_run_marker_without_plugin_data
rm -rf "$tmp/cfgdir"
out="$(run_hook "$tmp/absent.json" startup CLAUDE_CONFIG_DIR="$tmp/cfgdir")"
ok=0
[ -n "$(jq -r '.systemMessage // empty' <<<"$out")" ] && [ -f "$tmp/cfgdir/delegation/configure-offered.anthropic" ] && ok=1
check first_run_marker_without_plugin_data "$ok" "$out"

# hooks_json_shape
ok=0
jq -e '
  .hooks.PreToolUse[0].matcher == "Agent"
  and (.hooks.PreToolUse[0].hooks[0].command | endswith("/pin-subagent-model.sh"))
  and .hooks.PostToolUse[0].matcher == "Agent"
  and (.hooks.PostToolUse[0].hooks[0].command | endswith("/log-subagent.sh"))
  and .hooks.SessionStart[0].matcher == "startup|resume|clear|compact"
  and (.hooks.SessionStart[0].hooks[0].command | endswith("/session-note.sh"))
' "$HOOKS_JSON" >/dev/null 2>&1 && ok=1
check hooks_json_shape "$ok"

echo "Passed: $pass / $total"
if [ "$fail" -gt 0 ]; then
  printf 'FAILED: %s\n' "${failures[@]}"
  exit 1
fi
