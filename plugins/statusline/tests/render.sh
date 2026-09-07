#!/usr/bin/env bash
# Test runner for the context section of statusline.sh. Feeds synthetic
# status line payloads and temp transcripts through the script, with the base
# cache pointed at a temp dir through the STATUSLINE_CACHE_DIR seam, and checks
# the rendered label with ANSI colors stripped.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../bin/statusline.sh"
BASE_COLOR=$'\033[38;2;110;140;190m'
MODEL_COLOR=$'\033[38;2;90;220;200m'

if [ ! -x "$SCRIPT" ]; then
  echo "ERROR: script not found or not executable: $SCRIPT" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/cache"
export STATUSLINE_CACHE_DIR="$tmp/cache"
unset COLUMNS   # wrap tests set it explicitly; the default is a single line

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

# Assistant transcript record whose usage sums to the given token counts.
assistant() {
  printf '{"type":"assistant","message":{"usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":10}}}\n' "$1" "$2" "$3"
}

# Records a compaction writes: the boundary, then the summary as a user message.
compaction() {
  printf '{"type":"system","subtype":"compact_boundary","content":"Conversation compacted"}\n'
  printf '{"type":"user","isCompactSummary":true,"message":{"role":"user","content":"summary"}}\n'
}

# Payload with 60449 tokens in a 200k window, used_percentage 30.2 unless given;
# cwd is the temp dir so git stays out.
payload() {
  printf '{"workspace":{"current_dir":"%s"},"model":{"display_name":"Test"},"transcript_path":"%s","context_window":{"context_window_size":200000,"current_usage":{"input_tokens":32,"cache_creation_input_tokens":1205,"cache_read_input_tokens":59212},"used_percentage":%s}}' "$tmp" "$1" "${2:-30.2}"
}

render() { "$SCRIPT" | sed 's/\x1b\[[0-9;]*m//g'; }

# 1 when every needle appears in the haystack in the given order.
in_order() {
  local hay="$1" needle rest; shift
  rest="$hay"
  for needle in "$@"; do
    [[ "$rest" == *"$needle"* ]] || { echo 0; return; }
    rest="${rest#*"$needle"}"
  done
  echo 1
}

# 1 when every line of the stripped output is at most the given width.
lines_within() {
  local width="$1" line
  while IFS= read -r line; do
    [ "${#line}" -le "$width" ] || { echo 0; return; }
  done <<< "$2"
  echo 1
}
cache_of() { printf '%s/cache/statusline-base.%s' "$tmp" "$(basename "$1" .jsonl)"; }

# 1. Base comes from the first assistant turn; chat is the growth since.
{ assistant 2 18391 26445; assistant 32 1205 59212; } > "$tmp/t.jsonl"
out="$(payload "$tmp/t.jsonl" | render)"
check "numbers_before_percentages_with_split" "$([[ "$out" == *"60k/200k 30%  base 45k 22%  chat 16k 8%"* ]] && echo 1 || echo 0)"

# 2. Bar is stacked: base segments carry the base color, chat segments the gradient.
raw="$(payload "$tmp/t.jsonl" | "$SCRIPT")"
base_segments="$(printf '%s' "$raw" | grep -oF "${BASE_COLOR}█" | wc -l)"
gradient_segments="$(printf '%s' "$raw" | grep -oE $'\033\\[38;2;[0-9]+;[0-9]+;0m█' | wc -l)"
check "bar_stacks_base_then_chat" "$([ "$base_segments" = "4" ] && [ "$gradient_segments" = "2" ] && echo 1 || echo 0)"

# 3. After a compaction the base is the first turn after the boundary.
{ assistant 2 18391 26445; compaction; assistant 0 30000 0; } > "$tmp/c.jsonl"
out="$(payload "$tmp/c.jsonl" | render)"
check "compaction_rebases_base" "$([[ "$out" == *"60k/200k 30%  base 30k 15%  chat 30k 15%"* ]] && echo 1 || echo 0)"

# 4. Missing transcript: totals only, no split.
out="$(payload "$tmp/missing.jsonl" | render)"
check "missing_transcript_totals_only" "$([[ "$out" == *"60k/200k 30%"* ]] && [[ "$out" != *"base"* ]] && echo 1 || echo 0)"

# 5. Transcript without an assistant turn yet: totals only, no split.
printf '{"type":"user","message":{"role":"user","content":"hi"}}\n' > "$tmp/u.jsonl"
out="$(payload "$tmp/u.jsonl" | render)"
check "no_assistant_turn_totals_only" "$([[ "$out" == *"60k/200k 30%"* ]] && [[ "$out" != *"base"* ]] && echo 1 || echo 0)"

# 6. Base larger than the current total (tool results cleared): chat clamps to zero.
assistant 0 70000 0 > "$tmp/big.jsonl"
out="$(payload "$tmp/big.jsonl" | render)"
check "chat_clamps_at_zero" "$([[ "$out" == *"base 70k 35%  chat 0k 0%"* ]] && echo 1 || echo 0)"

# 7. No usage yet (session start): dashes.
out="$(printf '{"workspace":{"current_dir":"%s"},"model":{"display_name":"Test"},"context_window":{"context_window_size":200000,"current_usage":null,"used_percentage":null}}' "$tmp" | render)"
check "no_usage_shows_dashes" "$([[ "$out" == *" --"* ]] && [[ "$out" != *"k/"* ]] && echo 1 || echo 0)"

# 8. Compaction written but no reply after it yet: the old base is gone, totals only.
{ assistant 2 18391 26445; compaction; } > "$tmp/nb.jsonl"
out="$(payload "$tmp/nb.jsonl" | render)"
check "boundary_without_reply_totals_only" "$([[ "$out" == *"60k/200k 30%"* ]] && [[ "$out" != *"base"* ]] && echo 1 || echo 0)"

# 9. A render caches the base with the transcript size it scanned up to.
{ assistant 2 18391 26445; assistant 32 1205 59212; } > "$tmp/cw.jsonl"
payload "$tmp/cw.jsonl" | render > /dev/null
check "cache_written" "$([ "$(cat "$(cache_of "$tmp/cw.jsonl")" 2>/dev/null)" = "44838 $(stat -c %s "$tmp/cw.jsonl")" ] && echo 1 || echo 0)"

# 10. A cached base is used without re-reading the transcript.
{ assistant 2 18391 26445; assistant 32 1205 59212; } > "$tmp/cr.jsonl"
printf '20000 %s\n' "$(stat -c %s "$tmp/cr.jsonl")" > "$(cache_of "$tmp/cr.jsonl")"
out="$(payload "$tmp/cr.jsonl" | render)"
check "cached_base_used" "$([[ "$out" == *"base 20k 10%  chat 40k 20%"* ]] && echo 1 || echo 0)"

# 11. Growth without a compaction keeps the cached base and advances the scanned size.
assistant 2 18391 26445 > "$tmp/cg.jsonl"
printf '20000 %s\n' "$(stat -c %s "$tmp/cg.jsonl")" > "$(cache_of "$tmp/cg.jsonl")"
assistant 32 1205 59212 >> "$tmp/cg.jsonl"
out="$(payload "$tmp/cg.jsonl" | render)"
check "growth_keeps_cached_base" "$([[ "$out" == *"base 20k 10%"* ]] && [ "$(cat "$(cache_of "$tmp/cg.jsonl")")" = "20000 $(stat -c %s "$tmp/cg.jsonl")" ] && echo 1 || echo 0)"

# 12. A compaction appended after the scanned size invalidates the cached base.
assistant 2 18391 26445 > "$tmp/ci.jsonl"
printf '20000 %s\n' "$(stat -c %s "$tmp/ci.jsonl")" > "$(cache_of "$tmp/ci.jsonl")"
{ compaction; assistant 0 30000 0; } >> "$tmp/ci.jsonl"
out="$(payload "$tmp/ci.jsonl" | render)"
check "compaction_invalidates_cache" "$([[ "$out" == *"base 30k 15%  chat 30k 15%"* ]] && echo 1 || echo 0)"

# 13. The word base takes the base segment color.
raw="$(payload "$tmp/t.jsonl" | "$SCRIPT")"
check "base_word_in_base_color" "$([[ "$raw" == *"${BASE_COLOR}base"* ]] && echo 1 || echo 0)"

# 14. The word chat takes the color of the last filled segment: position 5 of 20 at 30%.
check "chat_word_matches_last_segment" "$([[ "$raw" == *$'\033[38;2;132;255;0mchat'* ]] && echo 1 || echo 0)"

# 15. Nothing filled yet: chat takes the first gradient color.
raw="$(payload "$tmp/t.jsonl" 1 | "$SCRIPT")"
check "chat_word_green_when_bar_empty" "$([[ "$raw" == *$'\033[38;2;0;255;0mchat'* ]] && echo 1 || echo 0)"

# 16. Model text is not in the base color.
check "model_color_distinct_from_base" "$([[ "$raw" == *"${MODEL_COLOR}Test"* ]] && echo 1 || echo 0)"

# 17. Wide terminal: everything on one line.
out="$(payload "$tmp/t.jsonl" | COLUMNS=200 render)"
check "wide_terminal_single_line" "$([ "$(printf '%s\n' "$out" | wc -l)" = "1" ] && echo 1 || echo 0)"

# 18. Narrow terminal: sections wrap onto further lines, each within the width
# minus a two-column margin, in their original order, none starting with a separator.
out="$(payload "$tmp/t.jsonl" | COLUMNS=60 render)"
joined="$(printf '%s' "$out" | tr '\n' ' ')"
check "narrow_terminal_wraps_sections" "$([ "$(printf '%s\n' "$out" | wc -l)" -ge 2 ] \
  && [ "$(lines_within 58 "$out")" = "1" ] \
  && [ "$(in_order "$joined" "Test" "60k/200k 30%" "base 45k 22%" "chat 16k 8%" "$tmp")" = "1" ] \
  && ! printf '%s\n' "$out" | grep -qE '^( |│)' && echo 1 || echo 0)"

# 19. A section wider than the screen sits on its own line and overflows.
out="$(payload "$tmp/t.jsonl" | COLUMNS=30 render)"
check "oversized_section_own_line" "$(printf '%s\n' "$out" | grep -qxF '██████▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 60k/200k 30%' && echo 1 || echo 0)"

# 20. No COLUMNS in the environment: one line, as when the width is unknown.
out="$(payload "$tmp/t.jsonl" | render)"
check "unknown_width_single_line" "$([ "$(printf '%s\n' "$out" | wc -l)" = "1" ] && echo 1 || echo 0)"

echo
echo "Passed: $pass / $((pass + fail))"
if [ "$fail" -gt 0 ]; then
  printf 'FAILED: %s\n' "${failures[@]}"
  exit 1
fi
exit 0
