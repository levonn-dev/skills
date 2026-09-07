#!/usr/bin/env bash
# managed by statusline@levonn-dev-skills: synced to ~/.claude/statusline-command.sh at session start. Edit the plugin copy, not this file.

# Claude Code status line:
#   model | effort | stacked context bar + tokens/% | base/chat split | output style | k8s | cwd | git
# Sections pack onto as many lines as the terminal width (COLUMNS) needs.

input=$(cat)
ESC=$'\033'   # real ESC byte: printf "%s" does NOT expand a literal "\033"

# ── Parse JSON fields ──────────────────────────────────────────────────────────
cwd=$(echo       "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo     "$input" | jq -r '.model.display_name // empty')
effort=$(echo    "$input" | jq -r '.effort.level // empty')
style=$(echo     "$input" | jq -r '.output_style.name // empty')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
used=$(echo      "$input" | jq -r '.context_window.used_percentage // empty')
size=$(echo      "$input" | jq -r '.context_window.context_window_size // empty')
total=$(echo     "$input" | jq -r '(.context_window.current_usage | .input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens) // empty')
transcript=$(echo "$input" | jq -r '.transcript_path // empty')

# Prefer used%; derive from remaining if only that is present.
if [ -z "$used" ] && [ -n "$remaining" ]; then
  used=$(awk "BEGIN{printf \"%.0f\", 100 - $remaining}")
fi

# ── Base context ──────────────────────────────────────────────────────────────
# The first turn carries everything present at startup: system prompt, tool and
# MCP definitions, memory, first prompt. Later turns add conversation. A
# compaction replaces the conversation, so the base restarts at the first turn
# after the latest boundary.
#
# The base is cached per session as "<base> <bytes scanned>". A refresh reuses
# it unless the bytes appended since carry a compaction marker; only then does
# it re-read the whole transcript.
read_base() {
  jq -rn '
    reduce inputs as $r ({base: null, reset: true};
      if ($r.subtype == "compact_boundary") or ($r.isCompactSummary == true) then .base = null | .reset = true
      elif .reset and $r.type == "assistant" and ($r.message.usage | type) == "object" then
        .base = ($r.message.usage | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)) | .reset = false
      else . end) | .base // empty' "$transcript" 2>/dev/null
}

base=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  cache="${STATUSLINE_CACHE_DIR:-${TMPDIR:-/tmp}}/statusline-base.$(basename "$transcript" .jsonl)"
  tsize=$(stat -c %s "$transcript" 2>/dev/null || echo 0)
  scanned=0
  [ -f "$cache" ] && read -r base scanned < "$cache"
  if [ -n "$base" ] && { [ "$tsize" -lt "$scanned" ] || tail -c +$((scanned + 1)) "$transcript" | grep -qE '"subtype":"compact_boundary"|"isCompactSummary":true'; }; then
    base=""
  fi
  [ -z "$base" ] && base=$(read_base)
  [ -n "$base" ] && printf '%s %s\n' "$base" "$tsize" > "$cache" 2>/dev/null
fi

# ── Context-used progress bar ──────────────────────────────────────────────────
# 20-segment bar filled to the used percentage. The base context fills the first
# segments in a steady blue-grey; conversation fills the rest in a gradient
# green(left)→yellow→red(right) across the bar's length, so a longer/redder bar
# means more context consumed.
SEGMENTS=20
BASE_COLOR="${ESC}[38;2;110;140;190m"

# Segments a percentage fills, rounded and clamped to the bar.
segments() {
  local n=$(( ($1 * SEGMENTS + 50) / 100 ))
  [ "$n" -gt "$SEGMENTS" ] && n=$SEGMENTS
  [ "$n" -lt 0 ]           && n=0
  printf '%s' "$n"
}

# Gradient color at a segment position, left in GRADIENT rather than printed:
# a subshell per segment would cost more than the rest of the script.
gradient_color() {
  local frac=$(( $1 * 100 / (SEGMENTS - 1) )) r g
  if [ "$frac" -le 50 ]; then                   # green -> yellow
    r=$(( frac * 255 * 2 / 100 )); g=255
  else                                          # yellow -> red
    r=255; g=$(( (100 - frac) * 255 * 2 / 100 ))
  fi
  GRADIENT="${ESC}[38;2;${r};${g};0m"
}

build_bar() {
  local filled="$1" base_filled="$2"
  local bar="" i
  for (( i=0; i<filled; i++ )); do
    if [ "$i" -lt "$base_filled" ]; then
      bar+="${BASE_COLOR}█"
    else
      gradient_color "$i"
      bar+="${GRADIENT}█"
    fi
  done
  bar+="${ESC}[38;5;238m"                         # dark grey for empty segments
  for (( i=filled; i<SEGMENTS; i++ )); do bar+="▒"; done
  bar+="${ESC}[0m"
  printf '%s' "$bar"
}

fmt_k()  { awk "BEGIN{printf \"%.0fk\", $1 / 1000}"; }
pct_of() { awk "BEGIN{printf \"%.0f\", $1 * 100 / $2}"; }

# Labels: tokens before every percentage. The total follows the bar, e.g.
# "60k/200k 30%"; the split is its own section, e.g. "base 45k 22%  chat 16k 8%".
# The words take their bar colors: base the base color, chat the gradient at
# the last filled segment.
base_filled=0
ctx_split=""
if [ -n "$used" ]; then
  used_round=$(printf '%.0f' "$used")
  filled=$(segments "$used_round")
  gradient_color $(( filled > 0 ? filled - 1 : 0 ))
  grey="${ESC}[38;2;180;180;180m"
  if [ -n "$total" ] && [ -n "$size" ]; then
    ctx_total="${grey}$(fmt_k "$total")/$(fmt_k "$size") ${used_round}%${ESC}[0m"
    if [ -n "$base" ]; then
      chat=$(( total - base ))
      [ "$chat" -lt 0 ] && chat=0
      base_pct=$(pct_of "$base" "$size")
      chat_pct=$(pct_of "$chat" "$size")
      base_filled=$(segments "$base_pct")
      [ "$base_filled" -gt "$filled" ] && base_filled=$filled
      ctx_split="${BASE_COLOR}base${ESC}[0m${grey} $(fmt_k "$base") ${base_pct}%${ESC}[0m"
      ctx_split+="  ${GRADIENT}chat${ESC}[0m${grey} $(fmt_k "$chat") ${chat_pct}%${ESC}[0m"
    fi
  else
    ctx_total="${grey}${used_round}% used${ESC}[0m"   # payload without token counts
  fi
  ctx_bar=$(build_bar "$filled" "$base_filled")
else
  ctx_bar=$(build_bar 0 0)
  ctx_total="${ESC}[38;5;238m--${ESC}[0m"
fi

# ── Model ────────────────────────────────────────────────────────────────────
model_str=""
[ -n "$model" ] && model_str="${ESC}[38;2;90;220;200m${model}${ESC}[0m"

# ── Effort ───────────────────────────────────────────────────────────────────
effort_str=""
if [ -n "$effort" ]; then
  case "$effort" in
    low)    effort_color="${ESC}[38;5;245m" ;;          # grey
    medium) effort_color="${ESC}[38;5;252m" ;;          # white
    high)   effort_color="${ESC}[38;2;255;220;80m" ;;   # yellow
    xhigh)  effort_color="${ESC}[38;2;255;165;0m" ;;    # orange
    max)    effort_color="${ESC}[38;2;255;80;80m" ;;    # red
    *)      effort_color="${ESC}[38;5;252m" ;;
  esac
  effort_str="${effort_color}[${effort}]${ESC}[0m"
fi

# ── Output style ───────────────────────────────────────────────────────────────
style_str=""
if [ -n "$style" ] && [ "$style" != "default" ]; then
  style_str="${ESC}[38;5;183mstyle:${style}${ESC}[0m"
fi

# ── Kubernetes context + namespace ────────────────────────────────────────────
k8s_str=""
if command -v kubectl > /dev/null 2>&1; then
  k8s_ctx=$(kubectl config current-context 2>/dev/null)
  if [ -n "$k8s_ctx" ]; then
    k8s_ns=$(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null)
    [ -z "$k8s_ns" ] && k8s_ns="default"
    k8s_str="${ESC}[38;2;100;200;255m${k8s_ctx}${ESC}[0m${ESC}[38;5;245m/${ESC}[0m${ESC}[38;2;180;230;180m${k8s_ns}${ESC}[0m"
  fi
fi

# ── Current directory ─────────────────────────────────────────────────────────
HOME_ESC=$(printf '%s' "$HOME" | sed 's/[\/&]/\\&/g')
# shellcheck disable=SC2001
display_cwd=$(echo "$cwd" | sed "s|^${HOME_ESC}|~|")
cwd_str="${ESC}[38;2;100;160;255m${display_cwd}${ESC}[0m"

# ── Git branch + dirty bits ───────────────────────────────────────────────────
git_str=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  BRANCH=$(git -C "$cwd" --no-optional-locks branch 2>/dev/null \
    | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/')
  if [ -n "$BRANCH" ]; then
    gitstatus=$(git -C "$cwd" --no-optional-locks status --porcelain=v1 2>/dev/null)
    ahead_behind=$(git -C "$cwd" --no-optional-locks status --branch --porcelain=v1 2>/dev/null | head -1)
    bits=""
    echo "$ahead_behind" | grep -q "ahead"   && bits="*${bits}"
    echo "$ahead_behind" | grep -q "behind"  && bits="x${bits}"
    echo "$gitstatus"    | grep -q "^R"      && bits=">${bits}"
    echo "$gitstatus"    | grep -q "^A"      && bits="+${bits}"
    echo "$gitstatus"    | grep -q "^??"     && bits="?${bits}"
    echo "$gitstatus"    | grep -q "^.D\|^D" && bits="-${bits}"
    echo "$gitstatus"    | grep -q "^.M\|^M" && bits="!${bits}"

    if [ -n "$bits" ]; then
      git_str="${ESC}[38;2;255;120;120m[${BRANCH} ${bits}]${ESC}[0m"
    else
      git_str="${ESC}[38;2;120;220;120m[${BRANCH}]${ESC}[0m"
    fi
  fi
fi

# ── Assemble ──────────────────────────────────────────────────────────────────
# Sections in display order, each with the separator shown before it when it
# continues a line. Claude Code sets COLUMNS for this script; a section that
# would overrun the width, minus a two-column margin, starts a new line. With
# no COLUMNS everything stays on one line.
sep="  "
gsep="${ESC}[38;5;238m │ ${ESC}[0m"

sections=()
seps=()
add() { seps+=("$1"); sections+=("$2"); }
[ -n "$model_str" ]  && add "" "$model_str"
[ -n "$effort_str" ] && add "$sep" "$effort_str"
add "$sep" "${ctx_bar} ${ctx_total}"
[ -n "$ctx_split" ]  && add "$sep" "$ctx_split"
[ -n "$style_str" ]  && add "$sep" "$style_str"
loc_sep="$gsep"
[ -n "$k8s_str" ]    && { add "$gsep" "$k8s_str"; loc_sep="$sep"; }
add "$loc_sep" "$cwd_str"
[ -n "$git_str" ]    && add "$sep" "$git_str"

# Visible width of a string, left in VISIBLE: color codes stripped, then
# characters counted (block glyphs are one column each under a UTF-8 locale).
# Chops code by code; an extglob substitution takes tens of ms on the bar.
visible_len() {
  local s="$1" text=""
  while [[ "$s" == *$'\033['* ]]; do
    text+="${s%%$'\033['*}"
    s="${s#*$'\033['}"
    s="${s#*m}"
  done
  text+="$s"
  VISIBLE=${#text}
}

budget=$(( ${COLUMNS:-0} - 2 ))
out=""
line=""
line_len=0
for i in "${!sections[@]}"; do
  visible_len "${sections[$i]}"; sec_len=$VISIBLE
  visible_len "${seps[$i]}";     sep_len=$VISIBLE
  if [ -z "$line" ]; then
    line="${sections[$i]}"; line_len=$sec_len
  elif [ "$budget" -le 0 ] || [ $(( line_len + sep_len + sec_len )) -le "$budget" ]; then
    line+="${seps[$i]}${sections[$i]}"; line_len=$(( line_len + sep_len + sec_len ))
  else
    out+="${line}"$'\n'
    line="${sections[$i]}"; line_len=$sec_len
  fi
done
out+="$line"

printf '%s\n' "$out"
