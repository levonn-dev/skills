#!/usr/bin/env bash
# delegation: PostToolUse hook on Agent. Appends one "completed" record per subagent run to the session log.
# Prints nothing and always exits 0.

set -uo pipefail

# shellcheck disable=SC1091  # path resolved at run time
source "$(dirname "$0")/../bin/provider.sh"

command -v jq >/dev/null 2>&1 || exit 0

# The payload stays on stdin: a single argv string is capped near 128 KiB.
record="$(jq -c --arg ts "$(delegation_now)" '
  select(.tool_name == "Agent") |
  def obj: if type == "object" then . else {} end;
  (.tool_input | obj) as $i |
  (.tool_response | obj) as $r |
  ($r.usage | obj) as $u |
  {
    kind: "completed",
    ts: $ts,
    session_id: (.session_id // null),
    tool_use_id: (.tool_use_id // null),
    agent_id: (.agent_id // null),
    subagent_type: ($i.subagent_type // null),
    requested_model: ($i.model // null),
    resolved_model: ($r.resolvedModel // null),
    models_used: ($r.modelsUsed // null),
    total_duration_ms: ($r.totalDurationMs // null),
    total_tool_use_count: ($r.totalToolUseCount // null),
    total_tokens: ($r.totalTokens // null),
    input_tokens: ($u.input_tokens // null),
    output_tokens: ($u.output_tokens // null),
    cache_creation_input_tokens: ($u.cache_creation_input_tokens // null),
    cache_read_input_tokens: ($u.cache_read_input_tokens // null),
    status: ($r.status // null),
    description: ($i.description // null)
  }' 2>/dev/null)"
[ -n "$record" ] || exit 0

session="$(printf '%s' "$record" | jq -r '.session_id // empty')"
# Keep the id to filename-safe characters so it cannot leave the log dir.
session="$(printf '%s' "$session" | tr -cd 'A-Za-z0-9._-')"
session="${session:-unknown}"
logdir="$(delegation_log_dir)"
{
  mkdir -p "$logdir" 2>/dev/null
  printf '%s\n' "$record" >> "$logdir/$session.jsonl"
} 2>/dev/null
exit 0
