#!/usr/bin/env bash
# managed by statusline@levonn-dev-skills: synced to ~/.claude/statusline-command.sh at session start. Edit the plugin copy, not this file.

# Claude Code status line - single line:
#   model | effort | context-used bar + % | output style | version | k8s | cwd | git

input=$(cat)
ESC=$'\033'   # real ESC byte: printf "%s" does NOT expand a literal "\033"

# ── Parse JSON fields ──────────────────────────────────────────────────────────
cwd=$(echo       "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo     "$input" | jq -r '.model.display_name // empty')
effort=$(echo    "$input" | jq -r '.effort.level // empty')
style=$(echo     "$input" | jq -r '.output_style.name // empty')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
used=$(echo      "$input" | jq -r '.context_window.used_percentage // empty')

# Prefer used%; derive from remaining if only that is present.
if [ -z "$used" ] && [ -n "$remaining" ]; then
  used=$(awk "BEGIN{printf \"%.0f\", 100 - $remaining}")
fi

# ── Context-used progress bar ──────────────────────────────────────────────────
# 20-segment bar filled to `pct`; gradient green(left)→yellow→red(right) across
# its length, so a longer/redder bar means more context consumed.
build_bar() {
  local pct="${1:-0}"
  local total=20
  local filled=$(( (pct * total + 50) / 100 ))   # round
  [ "$filled" -gt "$total" ] && filled=$total
  [ "$filled" -lt 0 ]        && filled=0
  local empty=$(( total - filled ))

  local bar="" i frac r g
  for (( i=0; i<filled; i++ )); do
    frac=$(( i * 100 / (total - 1) ))             # 0..100 by position
    if [ "$frac" -le 50 ]; then                   # green -> yellow
      r=$(( frac * 255 * 2 / 100 )); g=255
    else                                          # yellow -> red
      r=255; g=$(( (100 - frac) * 255 * 2 / 100 ))
    fi
    bar+="${ESC}[38;2;${r};${g};0m█"
  done
  bar+="${ESC}[38;5;238m"                         # dark grey for empty segments
  for (( i=0; i<empty; i++ )); do bar+="▒"; done
  bar+="${ESC}[0m"
  printf '%s' "$bar"
}

if [ -n "$used" ]; then
  used_round=$(printf '%.0f' "$used")
  ctx_bar=$(build_bar "$used_round")
  ctx_label="${ESC}[38;2;180;180;180m${used_round}% used${ESC}[0m"
else
  ctx_bar=$(build_bar 0)
  ctx_label="${ESC}[38;5;238m--${ESC}[0m"
fi

# ── Model ────────────────────────────────────────────────────────────────────
model_str=""
[ -n "$model" ] && model_str="${ESC}[38;2;150;180;255m${model}${ESC}[0m"

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

# ── Assemble single line ───────────────────────────────────────────────────────
# Order: model -> effort -> context (bar + used%) -> style | location
sep="  "
gsep="${ESC}[38;5;238m │ ${ESC}[0m"

line="${model_str}"
[ -n "$effort_str" ]  && line+="${sep}${effort_str}"
line+="${sep}${ctx_bar} ${ctx_label}"
[ -n "$style_str" ]   && line+="${sep}${style_str}"
line+="${gsep}"
[ -n "$k8s_str" ]     && line+="${k8s_str}${sep}"
line+="${cwd_str}"
[ -n "$git_str" ]     && line+="${sep}${git_str}"

printf '%s\n' "$line"
