#!/usr/bin/env bash
# Test runner for block-git-writes.sh.
# Pipes each tests/cases/*.json file through the hook script and asserts
# the exit code matches the expected code derived from the filename prefix.
#
# Filename convention:
#   allow_<name>.json  -> expects exit 0 (allow)
#   block_<name>.json  -> expects exit 2 (deny)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/block-git-writes.sh"
CASES_DIR="$SCRIPT_DIR/cases"

if [ ! -x "$HOOK" ]; then
  echo "ERROR: hook not found or not executable: $HOOK" >&2
  exit 1
fi

pass=0
fail=0
total=0
failures=()

for f in "$CASES_DIR"/*.json; do
  [ -e "$f" ] || continue
  total=$((total + 1))
  name="$(basename "$f" .json)"
  case "$name" in
    allow_*) expected=0 ;;
    block_*) expected=2 ;;
    *)
      echo "SKIP: $name (filename must start with allow_ or block_)"
      continue
      ;;
  esac
  actual_stderr=$(bash "$HOOK" < "$f" 2>&1 >/dev/null)
  actual=$?
  if [ "$actual" = "$expected" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failures+=("$name: expected $expected, got $actual${actual_stderr:+ (stderr: $actual_stderr)}")
  fi
done

echo
echo "Passed: $pass / $total"
if [ "$fail" -gt 0 ]; then
  echo "Failures:"
  for f in "${failures[@]}"; do
    echo "  - $f"
  done
  exit 1
fi
exit 0
