#!/usr/bin/env bash
# Test runner for log-subagent.sh.
# Each case pipes a PostToolUse payload through the hook with a fresh DELEGATION_LOG_DIR.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/log-subagent.sh"

if [ ! -x "$HOOK" ]; then
  echo "ERROR: hook not found or not executable: $HOOK" >&2
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

# fresh_logdir: print a log dir path that does not exist yet.
fresh_logdir() {
  printf '%s/log\n' "$(mktemp -d -p "$tmp" case.XXXXXX)"
}

# lines FILE: line count, 0 when the file is missing.
lines() {
  [ -f "$1" ] && wc -l < "$1" || echo 0
}

# payload [JQ_FILTER]: a full Agent payload, optionally reshaped by a jq filter.
payload() {
  jq -nc '{
    session_id: "s1", tool_use_id: "tu1", agent_id: "a1", hook_event_name: "PostToolUse", tool_name: "Agent",
    tool_input: {description: "explore", subagent_type: "Explore"},
    tool_response: {
      resolvedModel: "claude-haiku-5-5", modelsUsed: ["claude-haiku-5-5"],
      totalDurationMs: 12345, totalToolUseCount: 7, totalTokens: 40000,
      usage: {input_tokens: 1200, output_tokens: 800, cache_creation_input_tokens: 30000, cache_read_input_tokens: 8000},
      status: "completed"
    }
  } | '"${1:-.}"
}

# run_hook LOGDIR: feed stdin to the hook in a clean environment.
run_hook() {
  env -i PATH="$PATH" HOME="$tmp" DELEGATION_LOG_DIR="$1" bash "$HOOK"
}

# writes_completed_record
d="$(fresh_logdir)"
out="$(payload | run_hook "$d")"
ok=0
[ -z "$out" ] && [ "$(lines "$d/s1.jsonl")" -eq 1 ] &&
  jq -e '.kind == "completed" and .resolved_model == "claude-haiku-5-5" and .cache_read_input_tokens == 8000
    and .requested_model == null and .agent_id == "a1" and .subagent_type == "Explore"
    and .total_duration_ms == 12345 and .status == "completed" and .models_used == ["claude-haiku-5-5"]
    and keys_unsorted == ["kind","ts","session_id","tool_use_id","agent_id","subagent_type","requested_model","resolved_model","models_used","total_duration_ms","total_tool_use_count","total_tokens","input_tokens","output_tokens","cache_creation_input_tokens","cache_read_input_tokens","status","description"]' "$d/s1.jsonl" >/dev/null && ok=1
check writes_completed_record "$ok" "$(cat "$d"/s1.jsonl 2>/dev/null)"

# nulls_when_usage_missing
d="$(fresh_logdir)"
payload 'del(.tool_response.usage)' | run_hook "$d" >/dev/null
ok=0
jq -e '.input_tokens == null and .output_tokens == null' "$d/s1.jsonl" >/dev/null 2>&1 && ok=1
check nulls_when_usage_missing "$ok"

# nulls_when_sections_not_objects
d="$(fresh_logdir)"
payload '.tool_response = "oops" | .tool_input = null' | run_hook "$d" >/dev/null
payload '.tool_response.usage = "x"' | run_hook "$d" >/dev/null
ok=0
[ "$(lines "$d/s1.jsonl")" -eq 2 ] &&
  jq -s -e '.[0] | .kind == "completed" and .resolved_model == null and .input_tokens == null and .status == null and .description == null' "$d/s1.jsonl" >/dev/null &&
  jq -s -e '.[1] | .input_tokens == null and .resolved_model == "claude-haiku-5-5"' "$d/s1.jsonl" >/dev/null && ok=1
check nulls_when_sections_not_objects "$ok"

# appends_second_line
d="$(fresh_logdir)"
payload | run_hook "$d" >/dev/null
payload | run_hook "$d" >/dev/null
check appends_second_line "$([ "$(lines "$d/s1.jsonl")" -eq 2 ] && echo 1 || echo 0)"

# unknown_session_file
d="$(fresh_logdir)"
payload 'del(.session_id)' | run_hook "$d" >/dev/null
check unknown_session_file "$([ "$(lines "$d/unknown.jsonl")" -eq 1 ] && echo 1 || echo 0)"

# session_id_cannot_escape_logdir
d="$(fresh_logdir)"
payload '.session_id = "a/../evil"' | run_hook "$d" >/dev/null
ok=0
[ "$(lines "$d/a..evil.jsonl")" -eq 1 ] && [ ! -e "$(dirname "$d")/evil.jsonl" ] && ok=1
check session_id_cannot_escape_logdir "$ok"

# ignores_other_tools
d="$(fresh_logdir)"
payload '.tool_name = "Bash"' | run_hook "$d" >/dev/null
check ignores_other_tools "$([ -z "$(ls -A "$d" 2>/dev/null)" ] && echo 1 || echo 0)"

REPORT="$SCRIPT_DIR/../bin/report.sh"

# run_report LOGDIR CONFIG [ARGS]: run the report in a clean environment.
run_report() {
  local d="$1" c="$2"
  shift 2
  env -i PATH="$PATH" HOME="$tmp" DELEGATION_LOG_DIR="$d" DELEGATION_CONFIG="$c" bash "$REPORT" "$@"
}

# pin_line SESSION_FILE: append one pin record.
pin_line() {
  printf '%s\n' '{"kind":"pin","ts":"2026-11-06T10:00:00Z","session_id":"s1","tool_use_id":"tu1","subagent_type":"Explore","model":"haiku","source":"default"}' >> "$1"
}

# report_no_log
d="$(fresh_logdir)"
out="$(run_report "$d" "$tmp/none.json")"
check report_no_log "$(grep -q 'No subagent dispatches logged' <<<"$out" && echo 1 || echo 0)" "$out"

# report_one_row_one_pin
d="$(fresh_logdir)"
mkdir -p "$d"
pin_line "$d/s1.jsonl"
payload | run_hook "$d" >/dev/null
out="$(run_report "$d" "$tmp/none.json")"
ok=0
[ "$(grep -c 'claude-haiku-5-5' <<<"$out")" -eq 1 ] && grep -Eq 'Explore +- +claude-haiku-5-5 +12\.3s +7 +39200 +800$' <<<"$out" &&
  grep -qF 'pins fired: 1 (Explore->haiku: 1; source config: 0, default: 1)' <<<"$out" &&
  grep -qF 'Per-subagent token figures are the final request only, not whole-run spend.' <<<"$out" && ok=1
check report_one_row_one_pin "$ok" "$out"

# report_whole_second_duration
d="$(fresh_logdir)"
payload '.tool_response.totalDurationMs = 3000' | run_hook "$d" >/dev/null
out="$(run_report "$d" "$tmp/none.json")"
check report_whole_second_duration "$(grep -Eq ' 3\.0s ' <<<"$out" && echo 1 || echo 0)" "$out"

# report_config_defaults
d="$(fresh_logdir)"
out="$(run_report "$d" "$tmp/none.json" | head -n 1)"
check report_config_defaults "$([ "$out" = "Config: defaults" ] && echo 1 || echo 0)" "$out"

# report_config_present
d="$(fresh_logdir)"
echo '{"provider":"anthropic"}' > "$tmp/cfg.json"
out="$(run_report "$d" "$tmp/cfg.json" | head -n 1)"
check report_config_present "$([ "$out" = "Config: anthropic ($tmp/cfg.json)" ] && echo 1 || echo 0)" "$out"

# report_skips_malformed
d="$(fresh_logdir)"
mkdir -p "$d"
payload | run_hook "$d" >/dev/null
echo '{bad' >> "$d/s1.jsonl"
out="$(run_report "$d" "$tmp/none.json")"
rc=$?
check report_skips_malformed "$([ "$rc" -eq 0 ] && [ "$(grep -c 'claude-haiku-5-5' <<<"$out")" -eq 1 ] && echo 1 || echo 0)" "$out"

echo "Passed: $pass / $total"
if [ "$fail" -gt 0 ]; then
  printf 'FAIL: %s\n' "${failures[@]}"
  exit 1
fi
