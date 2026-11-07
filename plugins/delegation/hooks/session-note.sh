#!/usr/bin/env bash
# delegation: SessionStart hook that adds a short delegation note to context.
# The closing sentence reflects the config state. On the first startup on a
# machine with no config, it also shows the user a one-line nudge to run
# /delegation:configure, once per provider. Always exits 0.

set -uo pipefail

# shellcheck disable=SC1091  # path resolved at run time
source "$(dirname "$0")/../bin/provider.sh"

fixed='Delegation: dispatches that omit a model are pinned by subagent type (Anthropic API defaults: Explore to haiku, general-purpose to sonnet). When a subagent outlives the cache lifetime, the main conversation re-reads its context uncached on resume, so send independent work in one parallel wave and run dependent chains inside one orchestrator subagent. Keep reports under about 2,000 tokens; hand details over as files. /delegation:report shows what each subagent ran on.'

input="$(cat)"

# Without jq the config cannot be parsed; fall back to the no-file sentence.
if command -v jq >/dev/null 2>&1; then
  state_line="$(delegation_config_state)"
  start_source="$(jq -r '.source // empty' <<<"$input" 2>/dev/null)"
else
  state_line="none -"
  start_source=""
fi
state="${state_line%% *}"
config_provider="${state_line#* }"
detected="$(delegation_provider)"

case "$state" in
  ok) variable="Pins for ${detected} are configured." ;;
  mismatch) variable="The delegation config was made for ${config_provider}, this session is on ${detected}; defaults apply until /delegation:configure is re-run." ;;
  malformed) variable="The delegation config did not parse; defaults apply." ;;
  *) variable="This machine is on defaults; /delegation:configure sets pins for this environment." ;;
esac

context="${fixed} ${variable}"

# First startup without a config: nudge the user once per provider. The marker
# is written before the message so an unwritable dir means silence, not a nag.
message=""
if [ "$start_source" = startup ] && [ "$state" = none ]; then
  marker="$(delegation_marker_dir)/configure-offered.${detected}"
  if [ ! -e "$marker" ] && mkdir -p "$(dirname "$marker")" 2>/dev/null && : >"$marker" 2>/dev/null; then
    message="delegation: no subagent model pins are set for this machine (${detected}). Run /delegation:configure once to choose them."
  fi
fi

if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$context" --arg msg "$message" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}
     + (if $msg == "" then {} else {systemMessage: $msg} end)'
else
  printf '%s\n' "$context"
fi

exit 0
