# trim-output

A `PreToolUse` hook on Bash that trims the output of noisy test, build, and typecheck commands to the failures and the summary, so a long green run does not fill the context window.

When a command is exactly a listed runner plus plain arguments, the hook rewrites it so its combined output passes through a filter. Anything else runs untouched. The hook also runs inside subagents.

## Runners

- JavaScript: `npm test`, `npm run test`, `npm run build`, `pnpm test`, `pnpm run test`, `pnpm run build`, `yarn test`, `yarn build`, `bun test`, `npx jest`, `npx vitest`, `npx vitest run`, `tsc`, `npx tsc`
- Python: `pytest`, `python -m pytest`, `python3 -m pytest`
- Go: `go test`, `go build`, `go vet`
- Rust: `cargo test`, `cargo build`, `cargo check`, `cargo clippy`
- Java: `mvn test`, `mvn package`, `mvn verify`, `./mvnw test`, `./mvnw package`, `gradle test`, `gradle build`, `./gradlew test`, `./gradlew build`
- .NET: `dotnet test`, `dotnet build`
- Make: `make test`, `make build`

Plain arguments after the runner are allowed (`pytest -x tests/`). Commands with pipes, chains, redirects, substitutions, or variables are never rewritten.

## What the filter keeps

- Output of 80 lines or fewer passes through untouched.
- Longer output keeps every line matching a failure pattern (`[Ee]rror` followed by `:`, a space or `[`, `error TS<n>`, `error CS<n>`, `error MSB`, eslint's `  error  `, `ERROR`, `FAIL`, `[Ff]ailed`, `(fail)`, `panic:`, `Traceback`, `Exception`, `not ok`, `✗`, `×`, `assert`, and Go's `file.go:line:col: ` diagnostics). Patterns are matched as listed and case-sensitively; `Error`/`error` and `Failed`/`failed` are the only case variants covered, by enumeration. Over-matching is bounded by the 175-line cap plus the 4 lines after it.
- The last 25 lines are always kept, which is where runners print their summary.
- Failure-block lines are capped at 175; the rest are cut and counted.
- A footer line reports how many lines were kept of the total, and how many failure lines were cut.

The filter fails open: if `jq` is missing the hook does nothing and the command runs unchanged. The filter itself always exits 0.

## Permissions

- Installing the plugin approves the listed runners when they appear as a bare command with no shell metacharacters. The hook sets `permissionDecision` to `allow` on every rewrite.
- Permission rules are matched against the rewritten command, which no longer matches a rule written for the original, so the hook has to answer for it.
- Your `deny` and `ask` rules still win, because a hook cannot override them.
- The rewritten command is `set -o pipefail; { <command>; } 2>&1 | <filter>`, so the runner's exit status is preserved.

## What ships

- `hooks/hooks.json`: registers the hook on `PreToolUse` for `Bash`.
- `hooks/trim-noisy-command.sh`: matches the command against the runner list and emits the rewrite. Needs `jq`.
- `bin/trim-output.sh`: the filter.

## Install

```
/plugin install trim-output@levonn-dev-skills
```

## Tests

```
bash plugins/trim-output/tests/run.sh
bash plugins/trim-output/tests/filter.sh
```

`run.sh` feeds hook payloads from `tests/cases/` through the hook and checks which are rewritten and which pass through. `filter.sh` checks the filter on short, long, failing, and capped output.
