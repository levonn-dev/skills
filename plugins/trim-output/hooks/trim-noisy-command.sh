#!/usr/bin/env bash
# trim-output: PreToolUse hook that rewrites a bare test/build/typecheck
# command so its output passes through bin/trim-output.sh.
# Only a whole command that is a known runner plus plain arguments matches.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || exit 0

RUNNERS=(
  'npm test' 'npm run test' 'npm run build'
  'pnpm test' 'pnpm run test' 'pnpm run build'
  'yarn test' 'yarn build' 'bun test'
  'npx jest' 'npx vitest' 'npx vitest run'
  'pytest' 'python -m pytest' 'python3 -m pytest'
  'go test' 'go build' 'go vet'
  'cargo test' 'cargo build' 'cargo check' 'cargo clippy'
  'mvn test' 'mvn package' 'mvn verify' './mvnw test' './mvnw package'
  'gradle test' 'gradle build' './gradlew test' './gradlew build'
  'dotnet test' 'dotnet build'
  'make test' 'make build'
  'tsc' 'npx tsc'
)

input=$(cat)
[ "$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" = "Bash" ] || exit 0
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$command" ] || exit 0

alt=""
for r in "${RUNNERS[@]}"; do
  r="${r//./\\.}"
  r="${r//\//\\/}"
  alt+="${alt:+|}$r"
done
# Arguments exclude shell metacharacters, expansions, and control characters.
# shellcheck disable=SC2016  # literal characters, not expansions
args_class='[^;&|<>`$(){}#\\[:cntrl:]]'
re="^($alt)( ${args_class}*)?\$"
[[ "$command" =~ $re ]] || exit 0

tool_input=$(printf '%s' "$input" | jq -c '.tool_input')
new_command="set -o pipefail; { ${command}; } 2>&1 | '${CLAUDE_PLUGIN_ROOT}/bin/trim-output.sh'"
jq -n --argjson ti "$tool_input" --arg cmd "$new_command" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",updatedInput:($ti + {command:$cmd})}}'
exit 0
