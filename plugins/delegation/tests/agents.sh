#!/usr/bin/env bash
# Shape test for the delegation agents and skill. Claude Code silently ignores a
# misspelled frontmatter field, so this parses the frontmatter and checks every
# field against the expected table.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS="$ROOT/agents"
SKILL="$ROOT/skills/delegation/SKILL.md"

pass=0
fail=0
failures=()
total=0

check() {
  local name="$1" ok="$2"
  total=$((total + 1))
  if [ "$ok" = "OK" ]; then
    pass=$((pass + 1))
    echo "  ok   $name"
  else
    fail=$((fail + 1))
    failures+=("$name")
    echo "  FAIL $name"
  fi
}

# fm FILE: the lines between the first two --- markers
fm() { awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$1"; }
# field FILE KEY: value of a top-level frontmatter key
field() { fm "$1" | sed -n "s/^$2: *//p" | head -n 1; }

if [ ! -d "$AGENTS" ]; then
  echo "ERROR: agents directory missing: $AGENTS" >&2
  exit 1
fi

# name|model|effort|tools|omitClaudeMd
table='explorer|haiku|low|Read, Glob, Grep|true
reader|haiku|low|Read, Grep, Bash|true
test-runner|haiku|low|Bash, Read, Grep|true
researcher|sonnet|medium|WebFetch, WebSearch, Read|true
implementer|sonnet|medium|Read, Edit, Write, Glob, Grep, Bash|false
reviewer|sonnet|high|Read, Glob, Grep, Bash|false'

while IFS='|' read -r name model effort tools omit; do
  f="$AGENTS/$name.md"
  ok=OK
  [ -f "$f" ] || ok=BAD
  [ "$(field "$f" name)" = "$name" ] || ok=BAD
  desc="$(field "$f" description)"
  { [ -n "$desc" ] && [ "${#desc}" -lt 300 ]; } || ok=BAD
  [ "$(field "$f" model)" = "$model" ] || ok=BAD
  [ "$(field "$f" effort)" = "$effort" ] || ok=BAD
  [ "$(field "$f" tools)" = "$tools" ] || ok=BAD
  [ "$(field "$f" omitClaudeMd)" = "$omit" ] || ok=BAD
  [ "$(field "$f" maxTurns)" = "40" ] || ok=BAD
  fm "$f" | grep -A1 -x 'experimental:' | tail -n 1 | grep -qx '  cacheTtl: 1h' || ok=BAD
  body="$(awk '/^---$/{n++; next} n>=2{print}' "$f")"
  [ "$(printf '%s\n' "$body" | wc -l)" -lt 60 ] || ok=BAD
  printf '%s\n' "$body" | grep -qx '## Method' || ok=BAD
  printf '%s\n' "$body" | grep -qx '## Report' || ok=BAD
  check "agent_$name" "$ok"
done <<< "$table"

count="$(find "$AGENTS" -maxdepth 1 -name '*.md' | wc -l)"
if [ "$count" -eq 6 ]; then check six_agents_exactly OK; else check six_agents_exactly BAD; fi

ok=OK
[ -f "$SKILL" ] || ok=BAD
[ "$(field "$SKILL" name)" = "delegation" ] || ok=BAD
sdesc="$(field "$SKILL" description)"
{ [ -n "$sdesc" ] && [ "${#sdesc}" -lt 400 ]; } || ok=BAD
[ "$(awk '/^---$/{n++; next} n>=2{c++} END{print c+0}' "$SKILL")" -lt 140 ] || ok=BAD
check skill_frontmatter "$ok"

echo
echo "Passed: $pass / $total"
[ "$fail" -eq 0 ] || { printf 'Failed: %s\n' "${failures[*]}"; exit 1; }
