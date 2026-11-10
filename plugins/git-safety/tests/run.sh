#!/usr/bin/env bash
# Test runner for block-git-writes.sh.
# Pipes each tests/cases/*.json file through the hook script and asserts
# the exit code matches the expected code derived from the filename prefix.
#
# Filename convention:
#   allow_<name>.json  -> expects exit 0 (allow)
#   block_<name>.json  -> expects exit 2 (deny)
#
# __FIX__ in a case is replaced with a fixture directory holding a working
# tree (repo/), a bare git dir (bare/), a symlink into the tree (link) and a
# plain directory (plain/), for the cases about where a clone may land.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/block-git-writes.sh"
CASES_DIR="$SCRIPT_DIR/cases"

if [ ! -x "$HOOK" ]; then
  echo "ERROR: hook not found or not executable: $HOOK" >&2
  exit 1
fi

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/repo/.git" "$FIX/repo/sub" "$FIX/bare/objects" "$FIX/bare/refs" "$FIX/plain"
: > "$FIX/bare/HEAD"
ln -s "$FIX/repo/sub" "$FIX/link"

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
  actual_stderr=$(sed "s|__FIX__|$FIX|g" "$f" | bash "$HOOK" 2>&1 >/dev/null)
  actual=$?
  if [ "$actual" = "$expected" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failures+=("$name: expected $expected, got $actual${actual_stderr:+ (stderr: $actual_stderr)}")
  fi
done

# check <name> <expected> <actual>
check() {
  total=$((total + 1))
  if [ "$3" = "$2" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failures+=("$1: expected $2, got $3")
  fi
}

# A 200,000-character command, half bare and half quoted, with a write at its
# end: the hook must reach the write within 10 seconds. Timed with SECONDS,
# since macOS has no timeout command.
filler="$(head -c 100000 /dev/zero | tr '\0' 'a')"
started=$SECONDS
printf '{"tool_input":{"command":"echo %s \\"%s\\"; git push"}}' "$filler" "$filler" \
  | bash "$HOOK" >/dev/null 2>&1
actual=$?
[ $((SECONDS - started)) -le 10 ] || actual="$actual after more than 10s"
check "large_command" 2 "$actual"

# The hook must not lean on grep, whose -P macOS lacks: with a grep that only
# fails, a write still denies and a read still passes.
mkdir "$FIX/nogrep"
printf '#!/bin/sh\nexit 2\n' > "$FIX/nogrep/grep"
chmod +x "$FIX/nogrep/grep"
PATH="$FIX/nogrep:$PATH" bash "$HOOK" < "$CASES_DIR/block_push.json" >/dev/null 2>&1
check "write_without_grep" 2 $?
PATH="$FIX/nogrep:$PATH" bash "$HOOK" < "$CASES_DIR/allow_status.json" >/dev/null 2>&1
check "read_without_grep" 0 $?

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
