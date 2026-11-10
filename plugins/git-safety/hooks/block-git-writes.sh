#!/usr/bin/env bash
# git-safety: PreToolUse hook that blocks git commands modifying repo state.
# Reads JSON from stdin, sanitizes (strip heredocs, then quoted strings),
# scans for git invocations, exits 2 with stderr on any deny.

set -uo pipefail

# Byte-wise ASCII matching in bash and awk. In other locales a range such as
# [a-z] can take in letters outside it, and matching a long string slows down.
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
ALWAYS_BLOCK_RE='^(add|am|apply|checkout|cherry-pick|clean|commit|fetch|filter-branch|filter-repo|format-patch|gc|init|merge|mv|pack-refs|prune|pull|push|rebase|repack|replace|request-pull|reset|restore|revert|rm|send-email|switch|update-index|update-ref|worktree|write-tree|bisect|daemon|mailinfo|mailsplit|sparse-checkout|fast-import|p4|svn|bundle)$'

CONDITIONAL_RE='^(branch|tag|remote|stash|config|submodule|notes|reflog)$'

# What a plain argument may hold. Anything else (an expansion, a substitution,
# a glob, a brace, a quote, an escape, a comment) can change the argument list
# git receives in ways this hook cannot read.
PLAIN_TOKEN_RE='^[A-Za-z0-9._/:@+%=-]+$'

# A config key as written bare on a command line: section.name or
# section.subsection.name.
CONFIG_KEY_RE='^[A-Za-z][A-Za-z0-9-]*\.([A-Za-z0-9_./:@+-]*\.)?[A-Za-z][A-Za-z0-9-]*$'
CONFIG_READ_FLAG_RE='^(--global|--local|--system|--worktree|-z|--null|--show-origin|--show-scope|--includes|--no-includes|--type=[a-z-]+|--bool|--int|--bool-or-int|--path|--expiry-date)$'

# Clone flags that cannot move where the clone lands, and those that take a
# separate value. Any other flag denies the clone.
CLONE_FLAG_RE='^(-q|--quiet|-v|--verbose|--progress|-n|--no-checkout|--bare|--mirror|--single-branch|--no-single-branch|--no-tags|--recurse-submodules|--recursive|--shallow-submodules|--no-shallow-submodules|--sparse|--depth=[0-9]+|--branch=[^[:space:]]+|--filter=[^[:space:]]+|--jobs=[0-9]+)$'
CLONE_VALUE_FLAG_RE='^(--depth|-b|--branch|--filter|-j|--jobs)$'
CLONE_TARGET_RE='^(/[A-Za-z0-9._+-]+)+/?$'
DOT_SEGMENT_RE='(^|/)\.\.?(/|$)'

# ---- helpers ----

deny() {
  echo "git-safety blocked: 'git $1 ...' modifies repo state. Run it yourself if intended." >&2
  exit 2
}

deny_clone() {
  echo "git-safety blocked: 'git clone' is allowed only as 'git clone [flags] <repository> <absolute target>' with the target outside every git repository. Run it yourself if intended." >&2
  exit 2
}

# The arguments of a simple command with its redirections removed, or failure
# when a token is not plain or a redirection lacks a plain target. A rule that
# allows a command by its exact arguments must read them through this: a
# process substitution, a continued line or a `>|` would otherwise hide an
# argument from the count.
plain_args() {
  local redirect='^(&|[0-9]*)[<>]' bare='^(&|[0-9]*)[<>&]+$' attached='^(&|[0-9]*)[<>&]+(.*)$'
  local out="" want_target=0 tok
  local -a toks
  read -ra toks <<< "$1"
  for tok in ${toks[@]+"${toks[@]}"}; do
    if [ "$want_target" = 1 ]; then
      [[ "$tok" =~ $PLAIN_TOKEN_RE ]] || return 1
      want_target=0
      continue
    fi
    if [[ "$tok" =~ $redirect ]]; then
      if [[ "$tok" =~ $bare ]]; then
        want_target=1
        continue
      fi
      [[ "$tok" =~ $attached ]] && [[ "${BASH_REMATCH[2]}" =~ $PLAIN_TOKEN_RE ]] || return 1
      continue
    fi
    [[ "$tok" =~ $PLAIN_TOKEN_RE ]] || return 1
    out+="$tok "
  done
  [ "$want_target" = 0 ] || return 1
  printf '%s' "$out"
}

count_positionals() {
  local n=0 tok
  for tok in $1; do
    case "$tok" in
      -*) ;;
      *) n=$((n + 1)) ;;
    esac
  done
  printf '%s' "$n"
}

# True when no directory from the path's nearest existing ancestor up to the
# root is a working tree or a git dir. Symlinks are resolved first, so a link
# into a repository counts as inside it. Only an absolute path can be judged.
outside_any_repo() {
  local d="$1"
  [[ "$d" == /* ]] || return 1
  while [ ! -d "$d" ]; do
    d="${d%/*}"
    [ -z "$d" ] && d=/
  done
  d="$(cd "$d" 2>/dev/null && pwd -P)" || return 1
  while :; do
    if [ -e "$d/.git" ] || { [ -f "$d/HEAD" ] && [ -d "$d/objects" ] && [ -d "$d/refs" ]; }; then
      return 1
    fi
    [ "$d" = "/" ] && return 0
    d="${d%/*}"
    [ -z "$d" ] && d=/
  done
}

# clone changes no existing repository when it lands outside all of them, so
# one shape is allowed: `git clone [flags] <repository> <absolute target>`.
# No target, a relative or expanded one, or an unknown flag could put the
# clone in a working tree.
is_clone_outside_repos() {
  local args tok want_value=0 target
  local -a toks pos=()
  args=$(plain_args "$1") || return 1
  read -ra toks <<< "$args"
  for tok in ${toks[@]+"${toks[@]}"}; do
    if [ "$want_value" = 1 ]; then want_value=0; continue; fi
    case "$tok" in
      -*)
        if [[ "$tok" =~ $CLONE_VALUE_FLAG_RE ]]; then
          want_value=1
        elif ! [[ "$tok" =~ $CLONE_FLAG_RE ]]; then
          return 1
        fi
        ;;
      *) pos+=("$tok") ;;
    esac
  done
  [ "${#pos[@]}" -eq 2 ] || return 1
  target="${pos[1]}"
  [[ "$target" =~ $CLONE_TARGET_RE ]] || return 1
  if [[ "$target" =~ $DOT_SEGMENT_RE ]]; then return 1; fi
  outside_any_repo "$target"
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
      local plain positional=0 key=""
      # Only the query actions: a display flag such as --show-origin beside a
      # key and a value is still a write.
      if has_flag "$args" '^(--get|--get-all|--get-regexp|--get-urlmatch|-l|--list)$'; then
        if [ "$(count_positionals "$args")" -le 1 ]; then return 0; fi
        # The same rule with plain redirections set aside: `--get key 2>/dev/null`.
        if plain=$(plain_args "$args") && [ "$(count_positionals "$plain")" -le 1 ]; then return 0; fi
        return 1
      fi
      # A lone key with no value reads it: `git config --global user.name`.
      # Only scope and display flags may ride along, so a bundled or unknown
      # flag cannot turn the read into an edit.
      plain=$(plain_args "$args") || return 1
      for tok in $plain; do
        case "$tok" in
          -*) [[ "$tok" =~ $CONFIG_READ_FLAG_RE ]] || return 1 ;;
          *) positional=$((positional + 1)); key="$tok" ;;
        esac
      done
      if [ "$positional" -eq 1 ] && [[ "$key" =~ $CONFIG_KEY_RE ]]; then return 0; fi
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

# The subcommand's own arguments: what follows it up to the end of its
# simple command.
command_args() {
  local a="${1#"$2"}"
  a="${a#"${a%%[![:space:]]*}"}"
  a="${a%%&&*}"
  a="${a%%||*}"
  a="${a%%;*}"
  a="${a%%|*}"
  a="${a%%$'\n'*}"
  a="${a%%)*}"
  printf '%s' "$a"
}

scan_for_git() {
  local s="$1" rest="$1" before after subcmd args_after
  # What may follow `git` on its line. A newline ends the command instead.
  local blank=$' \t\r\f\v'
  # Matched in bash alone: macOS grep has no -P.
  while [[ "$rest" == *git["$blank"]* ]]; do
    before="${rest%%git["$blank"]*}"
    rest="${rest:${#before}+4}"
    # `git` ending a longer word, as in `legit`, is not the command.
    case "${before: -1}" in
      [a-zA-Z0-9_]) continue ;;
    esac
    after=$(walk_past_flags "$rest")
    subcmd=""
    if [[ "$after" =~ ^([a-zA-Z][a-zA-Z0-9_-]*) ]]; then
      subcmd="${BASH_REMATCH[1]}"
    fi
    [ -z "$subcmd" ] && continue
    if [[ "$subcmd" =~ $ALWAYS_BLOCK_RE ]]; then
      deny "$subcmd"
    fi
    if [ "$subcmd" = clone ]; then
      # A global flag or a git environment variable can move the work tree
      # away from the target, so clone is judged only when it stands bare.
      if [ "$after" != "${rest#"${rest%%[![:space:]]*}"}" ] || [[ "$s" == *GIT_* ]]; then
        deny_clone
      fi
      if ! is_clone_outside_repos "$(command_args "$after" "$subcmd")"; then
        deny_clone
      fi
      continue
    fi
    if [[ "$subcmd" =~ $CONDITIONAL_RE ]]; then
      args_after=$(command_args "$after" "$subcmd")
      if ! is_conditional_read_mode "$subcmd" "$args_after"; then
        deny "$subcmd"
      fi
    fi
  done
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

# Empties each quoted string to a bare quote pair and drops comments, so data
# is not scanned as a command. With `reveal`, a quoted plain word is written
# bare, as the shell reads it. In awk: bash measures the string per ${s:i:1}.
strip_quotes() {
  printf '%s' "$1" | awk -v reveal="${2:-}" -v plain="$PLAIN_TOKEN_RE" '
    # Set, not left unset: some awks stop treating a copied unset value as 0.
    BEGIN { out = 0 }
    function emit(s) {
      if (out == 0) printf "%s", s
      else held[out, ++count[out]] = s
    }
    # A substitution inside a double-quoted string is code. It goes to an
    # output line of its own, so the string stays one "" token where it stood.
    function open_code(kind, own_line) {
      sp++; ctx[sp] = kind; back[sp] = out; depth[sp] = 1
      if (own_line) out = ++lines
      if (kind == "`") ticks++
    }
    function close_code() {
      if (ctx[sp] == "`") ticks--
      out = back[sp]; sp--
    }
    # A # is a comment only where a word starts: an escaped blank or a
    # continued line before it keeps it inside the word.
    function starts_word(i) {
      if (i == 1) return last != "\\"
      return c[i - 1] ~ /[ \t;&|(<>]/ && c[i - 2] != "\\"
    }
    # True when characters a to b of the line are all plain. None is plain too.
    function plain_run(a, b,   j) {
      for (j = a; j <= b; j++) if (c[j] !~ plain) return 0
      return 1
    }
    {
      comment = 0
      for (k = 1; k <= sp; k++) spans[k] = 1
      kind = ctx[sp]
      if (NR > 1 && kind != "\047" && kind != "\042") emit("\n")
      # One character per element: substr() rescans the whole line in some awks.
      n = split($0, c, "")
      for (i = 1; i <= n; i++) {
        ch = c[i]
        kind = ctx[sp]
        if (kind == "\047" || kind == "\042") {
          if (ch == kind) {
            if (reveal && !spans[sp] && plain_run(start[sp], i - 1)) {
              for (j = start[sp]; j < i; j++) emit(c[j])
            } else emit(kind kind)
            sp--
          } else if (kind == "\042") {
            if (ch == "\\") i++
            else if (ch == "`") open_code(ch, 1)
            else if (ch == "$" && c[i + 1] == "(") { open_code("(", 1); i++ }
          }
          continue
        }
        # A comment ends with its line, or with the backticks it sits in.
        if (comment && !(ch == "`" && ticks)) continue
        comment = 0
        if (ch == "#" && starts_word(i)) { comment = 1; continue }
        if (ch == "\047" || ch == "\042") { sp++; ctx[sp] = ch; start[sp] = i + 1; spans[sp] = 0; continue }
        if (kind == "(") {
          if (ch == "(") depth[sp]++
          else if (ch == ")" && --depth[sp] == 0) { close_code(); continue }
        }
        if (ch == "`") {
          # Backticks met in code stay in place: only their extent is tracked.
          if (kind != "`") open_code(ch, 0)
          else {
            in_place = (out == back[sp])
            close_code()
            if (!in_place) continue
          }
        }
        emit(ch)
      }
      last = c[n]
    }
    END {
      for (k = 1; k <= lines; k++) {
        printf "\n"
        for (j = 1; j <= count[k]; j++) printf "%s", held[k, j]
      }
    }
  '
}

# ---- main ----

sanitized=$(strip_heredocs "$command")
blanked=$(strip_quotes "$sanitized")
scan_for_git "$blanked"
# `git "commit"` runs commit, so scan again with quoted plain words bare.
# The first scan keeps the quote markers the strict argument readers deny on.
revealed=$(strip_quotes "$sanitized" reveal)
[ "$revealed" = "$blanked" ] || scan_for_git "$revealed"
exit 0
