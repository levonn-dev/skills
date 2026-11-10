#!/usr/bin/env bash
# Sourced library: user settings.json helpers. Defines functions only.

# Path of the user settings file.
delegation_settings_path() {
  echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
}

# First managed file that sets KEY (inside top-level object PARENT when given), or "none".
delegation_managed_source() {
  local key="$1" parent="${2:-}" dir f
  local default="/etc/claude-code:/Library/Application Support/ClaudeCode:/mnt/c/Program Files/ClaudeCode:/c/Program Files/ClaudeCode"
  local -a dirs
  IFS=: read -ra dirs <<<"${DELEGATION_MANAGED_DIRS-$default}"
  for dir in ${dirs[@]+"${dirs[@]}"}; do
    [ -n "$dir" ] || continue
    for f in "$dir/managed-settings.json" "$dir"/managed-settings.d/*.json; do
      [ -f "$f" ] || continue
      if jq -e --arg k "$key" --arg p "$parent" \
        'if $p == "" then has($k) else ((.[$p] | type) == "object" and (.[$p] | has($k))) end' \
        "$f" >/dev/null 2>&1; then
        echo "$f"
        return 0
      fi
    done
  done
  echo none
}

# Run jq -c FILTER over the settings file, or over {} when it is absent or unparseable.
delegation_settings_get() {
  local filter="$1" file
  shift
  file="$(delegation_settings_path)"
  if [ -f "$file" ] && jq -e . "$file" >/dev/null 2>&1; then
    jq -c "$@" "$filter" "$file"
  else
    echo '{}' | jq -c "$@" "$filter"
  fi
}

# Succeed when the settings file is absent or exactly one JSON object.
delegation_settings_check() {
  local file
  file="$(delegation_settings_path)"
  [ -f "$file" ] || return 0
  if jq -e 'type == "object"' "$file" >/dev/null 2>&1 && [ "$(jq -s 'length' "$file" 2>/dev/null)" = 1 ]; then
    return 0
  fi
  echo "settings.json is not valid JSON; nothing written" >&2
  return 1
}

# Atomically replace the settings file with jq FILTER applied to it, keeping its mode.
delegation_settings_merge() {
  local filter="$1" file tmp target
  shift
  delegation_settings_check || return 1
  file="$(delegation_settings_path)"
  mkdir -p "$(dirname "$file")"
  [ -f "$file" ] || echo '{}' >"$file"
  # Replace the real file, not a symlink to it.
  target="$(readlink -f "$file" 2>/dev/null)"
  [ -n "$target" ] || target="$file"
  tmp="$(mktemp "$(dirname "$target")/.settings.XXXXXX")" || { echo "settings.json could not be written; nothing written" >&2; return 1; }
  # cp -p copies the mode portably; jq then truncates and fills the copy.
  if ! cp -p "$target" "$tmp"; then
    rm -f "$tmp"
    echo "settings.json could not be written; nothing written" >&2
    return 1
  fi
  if ! { jq "$@" "$filter" "$file" >"$tmp" && mv "$tmp" "$target"; }; then
    rm -f "$tmp"
    echo "settings.json could not be written; nothing written" >&2
    return 1
  fi
}
