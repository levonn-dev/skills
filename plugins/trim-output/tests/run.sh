#!/usr/bin/env bash
# Test runner for trim-noisy-command.sh.
# Filename convention in tests/cases:
#   rewrite_<name>.json -> hook must emit an allow decision with a piped command
#   pass_<name>.json    -> hook must exit 0 with empty stdout

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$PLUGIN_DIR/hooks/trim-noisy-command.sh"
CASES_DIR="$SCRIPT_DIR/cases"

if [ ! -x "$HOOK" ]; then
  echo "ERROR: hook not found or not executable: $HOOK" >&2
  exit 1
fi

pass=0
fail=0
total=0
failures=()

record() {
  if [ "$2" = ok ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failures+=("$1: $2")
  fi
}

check_rewrite() {
  local name="$1" f="$2" out rc orig
  out=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash "$HOOK" < "$f" 2>/dev/null)
  rc=$?
  if [ "$rc" != 0 ]; then record "$name" "exit $rc"; return; fi
  orig=$(jq -r '.tool_input.command' "$f")
  if printf '%s' "$out" | jq -e --arg orig "$orig" --slurpfile fx "$f" '
      .hookSpecificOutput as $h
      | $h.hookEventName == "PreToolUse"
      and $h.permissionDecision == "allow"
      and ($h.updatedInput.command | startswith("set -o pipefail; { "))
      and ($h.updatedInput.command | contains($orig + "; } 2>&1 | '"'"'"))
      and ($h.updatedInput.command | endswith("/bin/trim-output.sh'"'"'"))
      and (($h.updatedInput | del(.command)) == ($fx[0].tool_input | del(.command)))
    ' >/dev/null 2>&1; then
    record "$name" ok
  else
    record "$name" "output did not match: $out"
  fi
}

check_pass() {
  local name="$1" f="$2" out rc
  out=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash "$HOOK" < "$f" 2>/dev/null)
  rc=$?
  if [ "$rc" = 0 ] && [ -z "$out" ]; then record "$name" ok; else record "$name" "exit $rc, stdout: $out"; fi
}

for f in "$CASES_DIR"/*.json; do
  [ -e "$f" ] || continue
  name="$(basename "$f" .json)"
  case "$name" in
    rewrite_*) total=$((total + 1)); check_rewrite "$name" "$f" ;;
    pass_*)    total=$((total + 1)); check_pass "$name" "$f" ;;
    *) echo "SKIP: $name (filename must start with rewrite_ or pass_)" ;;
  esac
done

total=$((total + 1))
out=$(env -u CLAUDE_PLUGIN_ROOT bash "$HOOK" < "$CASES_DIR/rewrite_npm_test.json" 2>/dev/null)
rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ]; then record pass_no_plugin_root ok; else record pass_no_plugin_root "exit $rc, stdout: $out"; fi

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
