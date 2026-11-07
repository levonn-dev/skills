#!/usr/bin/env bash
# delegation: tabulate subagent runs and pin counts from the session log.
# Usage: report.sh [--all]   (--all reads every log file modified today)

set -uo pipefail

# shellcheck disable=SC1091  # path resolved at run time
source "$(dirname "$0")/provider.sh"

read -r state cfg_provider < <(delegation_config_state)
if [ "$state" = ok ]; then
  echo "Config: $cfg_provider ($(delegation_config_path))"
else
  echo "Config: defaults"
fi

logdir="$(delegation_log_dir)"
files=()
if [ -d "$logdir" ]; then
  if [ "${1:-}" = "--all" ]; then
    while IFS= read -r f; do files+=("$f"); done < <(find "$logdir" -maxdepth 1 -name '*.jsonl' -newermt "$(date +%Y-%m-%d)" | sort)
  else
    newest=""
    for f in "$logdir"/*.jsonl; do
      [ -e "$f" ] && { [ -z "$newest" ] || [ "$f" -nt "$newest" ]; } && newest="$f"
    done
    [ -n "$newest" ] && files=("$newest")
  fi
fi
if [ "${#files[@]}" -eq 0 ]; then
  echo "No subagent dispatches logged for this session yet."
  exit 0
fi

# Lines that fail to parse are dropped here.
records=""
for f in "${files[@]}"; do
  while IFS= read -r line || [ -n "$line" ]; do
    parsed="$(printf '%s' "$line" | jq -c . 2>/dev/null)" || continue
    [ -n "$parsed" ] && records+="$parsed"$'\n'
  done < "$f"
done

printf '%s' "$records" | jq -rs '
  .[] | select(type == "object" and .kind == "completed") |
  ((.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.input_tokens // 0)) as $ctx |
  [ (.ts // "-" | if length >= 19 then .[11:19] else . end),
    (.subagent_type // "-"),
    (.requested_model // "-"),
    (.resolved_model // "-"),
    (if .total_duration_ms == null then "-" else ((.total_duration_ms / 100 | round) as $t | "\($t / 10 | floor).\($t % 10)s") end),
    (.total_tool_use_count // "-"),
    $ctx,
    (.output_tokens // "-") ] | map(tostring) | join("\t")' |
  awk -F'\t' '
    BEGIN { fmt = "%-8s  %-16s  %-10s  %-20s  %8s  %5s  %9s  %7s\n"
            printf fmt, "time", "type", "requested", "resolved", "duration", "tools", "final_ctx", "output" }
    { printf fmt, $1, $2, $3, $4, $5, $6, $7, $8; ctx += $7; out += ($8 == "-" ? 0 : $8) }
    END { printf fmt, "totals", "", "", "", "", "", ctx + 0, out + 0 }'

printf '%s' "$records" | jq -rs '
  [.[] | select(type == "object" and .kind == "pin")] as $p |
  ($p | map("\(.subagent_type // "-")->\(.model // "-")") | reduce .[] as $k ([]; if index($k) then . else . + [$k] end)) as $keys |
  ($p | map("\(.subagent_type // "-")->\(.model // "-")")) as $all |
  "pins fired: \($p | length) (" +
  ([$keys[] as $k | "\($k): \([$all[] | select(. == $k)] | length)"] | join(", ")) +
  (if ($keys | length) > 0 then "; " else "" end) +
  "source config: \([$p[] | select(.source == "config")] | length), default: \([$p[] | select(.source == "default")] | length))"'

echo "Per-subagent token figures are the final request only, not whole-run spend."
exit 0
