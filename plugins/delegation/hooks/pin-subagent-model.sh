#!/usr/bin/env bash
# delegation: PreToolUse hook on Agent. Fills in a model alias when a dispatch left it blank.
# Prints an allow decision with updatedInput on a pin, nothing otherwise. Always exits 0.

set -uo pipefail

# shellcheck disable=SC1091  # path resolved at run time
source "$(dirname "$0")/../bin/provider.sh"

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"

# Rule 1: opt-out.
[ "${CLAUDE_DELEGATION_NO_PIN:-}" = 1 ] && exit 0

[ "$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" = Agent ] || exit 0
tool_input="$(printf '%s' "$input" | jq -c 'if (.tool_input | type) == "object" then .tool_input else empty end' 2>/dev/null)"
[ -n "$tool_input" ] || exit 0

# Rule 2: the dispatch already chose a model.
[ -z "$(printf '%s' "$tool_input" | jq -r '.model // empty')" ] || exit 0

# Rule 3: a session-wide subagent model override is set.
[ -z "${CLAUDE_CODE_SUBAGENT_MODEL:-}" ] || exit 0
[ -z "${CLAUDE_CODE_SUBAGENT_MODEL_FORCE:-}" ] || exit 0

type="$(printf '%s' "$tool_input" | jq -r '.subagent_type // empty')"
type="${type:-general-purpose}"

# Rule 4: forks inherit the parent model.
[ "$type" = fork ] && exit 0

alias=""
source=""
read -r state _ <<< "$(delegation_config_state)"
if [ "$state" = ok ]; then
  # Rule 5: pin from config.
  pin="$(jq -r --arg t "$type" '.pins[$t] // empty' "$(delegation_config_path)" 2>/dev/null)"
  case "$pin" in
    opus | sonnet | haiku | fable) alias="$pin"; source=config ;;
  esac
elif [ "$(delegation_provider)" = anthropic ]; then
  # Rule 6: Anthropic API defaults.
  case "$type" in
    Explore) alias=haiku; source=default ;;
    general-purpose) alias=sonnet; source=default ;;
  esac
fi
[ -n "$alias" ] || exit 0

# tool_input goes through stdin: a single argv string is capped near 128 KiB.
printf '%s' "$tool_input" | jq -c --arg m "$alias" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",updatedInput:(. + {model:$m})}}' || exit 0

session="$(printf '%s' "$input" | jq -r '.session_id // empty')"
# Keep the id to filename-safe characters so it cannot leave the log dir.
session="$(printf '%s' "$session" | tr -cd 'A-Za-z0-9._-')"
session="${session:-unknown}"
tool_use_id="$(printf '%s' "$input" | jq -r '.tool_use_id // empty')"
logdir="$(delegation_log_dir)"
{
  mkdir -p "$logdir" &&
    jq -nc --arg ts "$(delegation_now)" --arg s "$session" --arg id "$tool_use_id" \
      --arg t "$type" --arg m "$alias" --arg src "$source" \
      '{kind:"pin",ts:$ts,session_id:$s,tool_use_id:$id,subagent_type:$t,model:$m,source:$src}' \
      >> "$logdir/$session.jsonl"
} 2>/dev/null
exit 0
