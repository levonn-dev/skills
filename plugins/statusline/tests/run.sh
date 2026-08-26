#!/usr/bin/env bash
# Test runner for sync-statusline.sh. Points the hook at temp files through
# the CLAUDE_PLUGIN_ROOT and STATUSLINE_TARGET seams and checks what it
# leaves behind in each state the target can be in.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/sync-statusline.sh"
MARKER='managed by statusline@levonn-dev-skills'

if [ ! -x "$HOOK" ]; then
  echo "ERROR: hook not found or not executable: $HOOK" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

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

# Fresh plugin root with a marked source script for each case.
setup() {
  rm -rf "$tmp/root" "$tmp/target"
  mkdir -p "$tmp/root/bin"
  printf '#!/usr/bin/env bash\n# %s\necho new\n' "$MARKER" > "$tmp/root/bin/statusline.sh"
}
run() { CLAUDE_PLUGIN_ROOT="$tmp/root" STATUSLINE_TARGET="$tmp/target" "$HOOK"; }

# 1. No target: install has not run, hook must not create one.
setup; run
check "target_missing_stays_missing" "$([ ! -e "$tmp/target" ] && echo 1 || echo 0)"

# 2. Hand-written target without the marker: untouched.
setup; printf '#!/usr/bin/env bash\necho mine\n' > "$tmp/target"; run
check "unmarked_target_untouched" "$(grep -q 'echo mine' "$tmp/target" && ! grep -q 'echo new' "$tmp/target" && echo 1 || echo 0)"

# 3. Marked target with older content: overwritten with the source.
setup; printf '#!/usr/bin/env bash\n# %s\necho old\n' "$MARKER" > "$tmp/target"; run
check "marked_stale_target_updated" "$(cmp -s "$tmp/root/bin/statusline.sh" "$tmp/target" && echo 1 || echo 0)"

# 4. Marked target already identical: left as is.
setup; cp "$tmp/root/bin/statusline.sh" "$tmp/target"; touch -d '2000-01-01' "$tmp/target"; run
check "identical_target_not_rewritten" "$([ "$(stat -c %Y "$tmp/target")" = "$(date -d '2000-01-01' +%s)" ] && echo 1 || echo 0)"

# 5. Source missing (broken install): nothing happens, exit 0.
setup; rm "$tmp/root/bin/statusline.sh"; printf '# %s\necho old\n' "$MARKER" > "$tmp/target"; run; rc=$?
check "missing_source_noop" "$([ "$rc" = "0" ] && grep -q 'echo old' "$tmp/target" && echo 1 || echo 0)"

# 6. Hook is always exit 0 and silent.
setup; printf '# %s\necho old\n' "$MARKER" > "$tmp/target"; out="$(run)"; rc=$?
check "silent_exit_zero" "$([ "$rc" = "0" ] && [ -z "$out" ] && echo 1 || echo 0)"

echo
echo "Passed: $pass / $((pass + fail))"
if [ "$fail" -gt 0 ]; then
  printf 'FAILED: %s\n' "${failures[@]}"
  exit 1
fi
exit 0
