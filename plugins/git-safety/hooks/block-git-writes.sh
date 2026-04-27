#!/usr/bin/env bash
# git-safety: PreToolUse hook that blocks git commands modifying repo state.
# Reads JSON from stdin, sanitizes (strip heredocs, then quoted strings),
# scans for git invocations, exits 2 with stderr on any deny.

set -uo pipefail

# Force byte-mode string handling. grep -ob emits byte offsets, but bash
# ${var:pos} uses Unicode characters by default. Multi-byte chars in the
# command string (e.g. accented paths, CJK) would shift the offsets and
# let writes slip through. LC_ALL=C makes everything byte-aligned.
export LC_ALL=C

# Hard dependency. If jq is missing, the command-extraction below would
# silently produce an empty string and we'd fail open. Refuse all bash
# instead so the failure is surfaced.
if ! command -v jq >/dev/null 2>&1; then
  echo "git-safety: jq not found. Install jq to enforce git write blocking." >&2
  exit 2
fi

# ---- read input ----
input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
if [ -z "$command" ]; then
  exit 0
fi

# ---- subcommand classification ----
ALWAYS_BLOCK_RE='^(add|am|apply|checkout|cherry-pick|clean|clone|commit|fetch|filter-branch|filter-repo|format-patch|gc|init|merge|mv|pack-refs|prune|pull|push|rebase|repack|replace|request-pull|reset|restore|revert|rm|send-email|switch|update-index|update-ref|worktree|write-tree|bisect|daemon|mailinfo|mailsplit|sparse-checkout|fast-import|p4|svn|bundle)$'

CONDITIONAL_RE='^(branch|tag|remote|stash|config|submodule|notes|reflog)$'

# ---- helpers ----

deny() {
  echo "git-safety blocked: 'git $1 ...' modifies repo state. Run it yourself if intended." >&2
  exit 2
}

has_flag() {
  local args="$1" pattern="$2" tok
  for tok in $args; do
    if [[ "$tok" =~ $pattern ]]; then
      return 0
    fi
  done
  return 1
}

is_conditional_read_mode() {
  local subcmd="$1" args="$2" tok first
  case "$subcmd" in
    branch)
      if has_flag "$args" '^(-d|-D|-m|-M|-c|-C|--copy|--move|--delete|--track|--set-upstream-to|-u|--unset-upstream)$'; then
        return 1
      fi
      # If a query flag is present, any positional arg is the query target,
      # not a branch name being created. Allow.
      if has_flag "$args" '^(-l|--list|-v|-vv|-a|--all|-r|--remotes|--show-current|--contains|--no-contains|--merged|--no-merged|--points-at|--column)$'; then
        return 0
      fi
      for tok in $args; do
        case "$tok" in
          -*) ;;
          *) return 1 ;;
        esac
      done
      return 0
      ;;
    tag)
      if has_flag "$args" '^(-d|-a|-s|-f|--force|--delete|--sign|--annotate)$'; then
        return 1
      fi
      # Same reasoning as branch: query flag + positional = query target.
      # `-n` and `-n<num>` print N lines of annotation (read-only).
      if has_flag "$args" '^(-l|--list|--contains|--no-contains|--merged|--no-merged|--points-at|--verify|-n[0-9]*)$'; then
        return 0
      fi
      for tok in $args; do
        case "$tok" in
          -*) ;;
          *) return 1 ;;
        esac
      done
      return 0
      ;;
    remote)
      read -r first _ <<< "$args"
      case "$first" in
        ''|-v|--verbose|show|get-url) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    stash)
      read -r first _ <<< "$args"
      case "$first" in
        list|show) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    config)
      if has_flag "$args" '^(--add|--unset|--unset-all|--replace-all|--rename-section|--remove-section|--edit|-e)$'; then
        return 1
      fi
      if has_flag "$args" '^(--get|--get-all|--get-regexp|--get-urlmatch|-l|--list|--show-origin|--show-scope)$'; then
        local positional=0
        for tok in $args; do
          case "$tok" in
            -*) ;;
            *) positional=$((positional + 1)) ;;
          esac
        done
        if [ "$positional" -le 1 ]; then return 0; else return 1; fi
      fi
      return 1
      ;;
    submodule)
      read -r first _ <<< "$args"
      case "$first" in
        ''|status|foreach|summary) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    notes)
      read -r first _ <<< "$args"
      case "$first" in
        ''|list|show) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    reflog)
      read -r first _ <<< "$args"
      case "$first" in
        ''|show|exists) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *)
      return 0
      ;;
  esac
}

# Walk past optional global git flags. Returns the rest of the string starting
# at the subcommand (or empty if no subcommand).
walk_past_flags() {
  local rest="$1"
  while true; do
    rest="${rest#"${rest%%[![:space:]]*}"}"
    if [ -z "$rest" ]; then printf '%s' ""; return; fi
    if [[ "$rest" =~ ^(-C|-c)[[:space:]]+[^[:space:]]+(.*)$ ]]; then
      rest="${BASH_REMATCH[2]}"
      continue
    fi
    if [[ "$rest" =~ ^(--git-dir|--work-tree|--namespace|--exec-path)=[^[:space:]]+(.*)$ ]]; then
      rest="${BASH_REMATCH[2]}"
      continue
    fi
    if [[ "$rest" =~ ^(--no-pager|--paginate|--no-replace-objects|--bare|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|--html-path|--man-path|--info-path|-p|-P)([[:space:]]|$)(.*)$ ]]; then
      rest="${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
      continue
    fi
    printf '%s' "$rest"
    return
  done
}

scan_for_git() {
  local s="$1" line offset prev rest after subcmd args_after
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    offset="${line%%:*}"
    if [ "$offset" -gt 0 ]; then
      prev="${s:offset-1:1}"
      case "$prev" in
        [a-zA-Z0-9_]) continue ;;
      esac
    fi
    rest="${s:offset+4}"
    after=$(walk_past_flags "$rest")
    subcmd=""
    if [[ "$after" =~ ^([a-zA-Z][a-zA-Z0-9_-]*) ]]; then
      subcmd="${BASH_REMATCH[1]}"
    fi
    [ -z "$subcmd" ] && continue
    if [[ "$subcmd" =~ $ALWAYS_BLOCK_RE ]]; then
      deny "$subcmd"
    fi
    if [[ "$subcmd" =~ $CONDITIONAL_RE ]]; then
      args_after="${after#"$subcmd"}"
      args_after="${args_after#"${args_after%%[![:space:]]*}"}"
      args_after="${args_after%%&&*}"
      args_after="${args_after%%||*}"
      args_after="${args_after%%;*}"
      args_after="${args_after%%|*}"
      args_after="${args_after%%$'\n'*}"
      args_after="${args_after%%)*}"
      if ! is_conditional_read_mode "$subcmd" "$args_after"; then
        deny "$subcmd"
      fi
    fi
  done < <(printf '%s' "$s" | grep -obP '\bgit\s+' || true)
}

# ---- sanitize ----

strip_heredocs() {
  local s="$1"
  printf '%s' "$s" | awk '
    BEGIN { in_heredoc = 0; dash = 0; delim = "" }
    {
      if (in_heredoc) {
        line = $0
        if (dash) { sub(/^\t+/, "", line) }
        if (line == delim) {
          in_heredoc = 0
          print $0
        }
        next
      }
      n = match($0, /<<-?[[:space:]]*[\047\042]?[A-Za-z_][A-Za-z0-9_]*[\047\042]?/)
      if (n > 0) {
        token = substr($0, RSTART, RLENGTH)
        dash = 0
        rest = token
        sub(/^<</, "", rest)
        if (substr(rest, 1, 1) == "-") {
          dash = 1
          sub(/^-/, "", rest)
        }
        sub(/^[[:space:]]+/, "", rest)
        gsub(/^[\047\042]/, "", rest)
        gsub(/[\047\042]$/, "", rest)
        delim = rest
        in_heredoc = 1
      }
      print $0
    }
  '
}

strip_quotes() {
  local s="$1" out="" i=0 n ch in_single=0 in_double=0
  n=${#s}
  while [ "$i" -lt "$n" ]; do
    ch="${s:i:1}"
    if [ "$in_single" = 1 ]; then
      if [ "$ch" = "'" ]; then in_single=0; out+="'"; fi
      i=$((i + 1)); continue
    fi
    if [ "$in_double" = 1 ]; then
      if [ "$ch" = '\' ] && [ "$((i + 1))" -lt "$n" ]; then
        i=$((i + 2)); continue
      fi
      if [ "$ch" = '"' ]; then in_double=0; out+='"'; fi
      i=$((i + 1)); continue
    fi
    case "$ch" in
      "'") in_single=1; out+="'" ;;
      '"') in_double=1; out+='"' ;;
      *)   out+="$ch" ;;
    esac
    i=$((i + 1))
  done
  printf '%s' "$out"
}

# ---- main ----

sanitized=$(strip_heredocs "$command")
sanitized=$(strip_quotes "$sanitized")
scan_for_git "$sanitized"
exit 0
