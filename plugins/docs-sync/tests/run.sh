#!/usr/bin/env bash
# docs-sync test runner. Each case injects a fake `git status` via env and a
# stop flag via stdin, then checks whether the hook blocks (asks for docs) or
# allows the stop. Hermetic: no real repo, no git writes.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../hooks/check-docs.sh"
CASES="$HERE/cases"

pass=0
fail=0

for case_file in "$CASES"/*.json; do
  name="$(basename "$case_file" .json)"
  status="$(jq -r '.status | join("\n")' "$case_file")"
  active="$(jq -r '.stop_hook_active // false' "$case_file")"
  expect="$(jq -r '.expect' "$case_file")"
  input="$(jq -n --argjson a "$active" '{stop_hook_active: $a}')"
  out="$(printf '%s' "$input" | DOCS_SYNC_TEST=1 DOCS_SYNC_TEST_STATUS="$status" bash "$HOOK" 2>/dev/null)"
  if printf '%s' "$out" | grep -q '"decision": *"block"'; then
    got="block"
  else
    got="allow"
  fi
  if [ "$got" = "$expect" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL: $name (expected $expect, got $got)"
    fail=$((fail + 1))
  fi
done

echo "Passed: $pass / $((pass + fail))"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
