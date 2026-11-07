#!/usr/bin/env bash
# Test runner for pin-subagent-model.sh.
# Each tests/cases/<name>.json is piped through the hook in a clean environment.
#
# Filename convention:
#   pin_<name>.json  -> expects an allow with updatedInput.model and one pin record
#   pass_<name>.json -> expects empty stdout and no record
# Optional sidecars: <name>.env (KEY=VALUE lines), <name>.config.json (DELEGATION_CONFIG). A malformed config uses .config.txt.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/pin-subagent-model.sh"
CASES_DIR="$SCRIPT_DIR/cases"

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

check_pin() {
  local f="$1" out="$2" logdir="$3" model source type files n
  model="$(jq -r '._expect.model' "$f")"
  source="$(jq -r '._expect.source' "$f")"
  type="$(jq -r '.tool_input.subagent_type // "general-purpose"' "$f")"
  [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision')" = allow ] || { echo "decision not allow"; return 1; }
  [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.model')" = "$model" ] || { echo "wrong model"; return 1; }
  printf '%s' "$out" | jq -e --slurpfile fx "$f" \
    '.hookSpecificOutput.updatedInput | del(.model) == $fx[0].tool_input' >/dev/null || { echo "updatedInput differs from tool_input"; return 1; }
  files=("$logdir"/*)
  if [ "${#files[@]}" != 1 ] || [ ! -f "${files[0]}" ]; then echo "log dir does not hold exactly one file"; return 1; fi
  n="$(wc -l < "${files[0]}")"
  [ "$n" -eq 1 ] || { echo "log has $n lines"; return 1; }
  jq -e --arg m "$model" --arg s "$source" --arg t "$type" \
    '.kind == "pin" and .model == $m and .source == $s and .tool_use_id == "tu1" and .subagent_type == $t' \
    "${files[0]}" >/dev/null || { echo "bad record: $(cat "${files[0]}")"; return 1; }
}

# A prompt too large for one argv string is generated here instead of stored.
mkdir -p "$tmp/gen"
head -c 200000 /dev/zero | tr '\0' x | jq -Rs '{session_id:"s1",tool_use_id:"tu1",hook_event_name:"PreToolUse",tool_name:"Agent",tool_input:{prompt:.,description:"explore",subagent_type:"Explore"},_expect:{model:"haiku",source:"default"}}' > "$tmp/gen/pin_huge_prompt.json"

for f in "$CASES_DIR"/*.json "$tmp/gen"/*.json; do
  [ -e "$f" ] || continue
  name="$(basename "$f" .json)"
  case "$name" in
    *.config) continue ;;
    pin_* | pass_*) ;;
    *)
      echo "SKIP: $name (filename must start with pin_ or pass_)"
      continue
      ;;
  esac
  total=$((total + 1))
  logdir="$(mktemp -d "$tmp/log.XXXXXX")"
  cfg="$tmp/missing-config.json"
  # .config.txt holds deliberately malformed configs so repo-wide JSON checks pass.
  for ext in json txt; do
    [ -e "$CASES_DIR/$name.config.$ext" ] && { cfg="$CASES_DIR/$name.config.$ext"; break; }
  done
  extra=()
  if [ -e "$CASES_DIR/$name.env" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && extra+=("$line")
    done < "$CASES_DIR/$name.env"
  fi
  out="$(env -i PATH="$PATH" HOME="$tmp" DELEGATION_LOG_DIR="$logdir" DELEGATION_CONFIG="$cfg" "${extra[@]}" bash "$HOOK" < "$f" 2>/dev/null)"
  code=$?
  msg=""
  if [ "$code" != 0 ]; then
    msg="exit $code"
  elif [ "${name#pin_}" != "$name" ]; then
    msg="$(check_pin "$f" "$out" "$logdir")" || true
  else
    [ -z "$out" ] || msg="unexpected stdout: $out"
    [ -z "$(ls -A "$logdir")" ] || msg="${msg:+$msg; }log dir not empty"
  fi
  if [ -z "$msg" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failures+=("$name: $msg")
  fi
done

echo
echo "Passed: $pass / $total"
if [ "$fail" -gt 0 ]; then
  echo "Failures:"
  for m in "${failures[@]}"; do
    echo "  - $m"
  done
  exit 1
fi
exit 0
