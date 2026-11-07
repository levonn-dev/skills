# levonn-dev-skills

Personal Claude Code plugin marketplace.

## Plugins

Each plugin has its own README with what ships, install, and tests.

- [coding-guidelines](plugins/coding-guidelines/README.md): behavioral guidelines for clean, surgical, goal-driven coding, injected every session by a `SessionStart` hook; ships the `finding-verifier` agent that adversarially checks review findings before they drive edits.
- [git-safety](plugins/git-safety/README.md): advisory skill + `PreToolUse` hook that hard-denies git write commands; `/git-safety:commit-queue` partitions the working tree into verified single-line commit commands for you to run. Read-only git is unaffected.
- [manual-work-coordination](plugins/manual-work-coordination/README.md): stop cleanly when you take a task over by hand, and trust your manual work on resume instead of redoing or re-verifying it.
- [docs-sync](plugins/docs-sync/README.md): skill + `Stop` hook that keeps documentation in step with changes, including request collections, test scripts, runbooks, dashboards, and alert rules. The hook nudges when a turn ends with file changes but no docs touched; read-only git, loop-safe.
- [friction](plugins/friction/README.md): skill + `SessionStart` hook that logs small frictions (retries, flaky commands, misleading errors, gotchas) to `FRICTION.md` in the moment; `/friction:find` sweeps the session for missed ones; `/friction:review` walks the open entries by root cause and fixes, tracks, or drops each one.
- [statusline](plugins/statusline/README.md): a managed status line (model, effort, context bar, prompt cache state, kubectl context, cwd, git state). `/statusline:install` wires it into settings once; a `SessionStart` hook syncs the installed copy whenever the plugin updates.
- [trim-output](plugins/trim-output/README.md): `PreToolUse` hook that trims the output of bare test, build, and typecheck commands (`go test`, `npm test`, `tsc`, and others) to failure blocks and the tail before it reaches the model; the runner's exit status is preserved.
- [delegation](plugins/delegation/README.md): pins cheaper model aliases onto subagent dispatches that name no model, per environment; ships its own delegation agents; `/delegation:configure` sets pins once per machine and `/delegation:report` shows what each subagent ran on.

## Install

```
/plugin marketplace add levonn-dev/skills
/plugin install coding-guidelines@levonn-dev-skills
/plugin install git-safety@levonn-dev-skills
```

## Disable per-project

Add to `<repo>/.claude/settings.local.json`:

```json
{ "enabledPlugins": { "git-safety@levonn-dev-skills": false } }
```

## Versioning

Each plugin carries a version in two places that must always match:

- `plugins/<name>/.claude-plugin/plugin.json`
- the plugin's entry in `.claude-plugin/marketplace.json`

When you change a plugin, bump both:

- patch (`0.1.0` to `0.1.1`): non-functional changes (comments, docs, tests).
- minor (`0.1.0` to `0.2.0`): new backward-compatible behavior.
- major (`0.1.0` to `1.0.0`): breaking changes to behavior.

Bump `metadata.version` in `marketplace.json` when the catalog itself changes (a plugin added or removed). CI fails on any version drift between a `plugin.json` and its marketplace entry.

## Tests

```
bash plugins/git-safety/tests/run.sh
bash plugins/docs-sync/tests/run.sh
bash plugins/statusline/tests/run.sh
bash plugins/statusline/tests/render.sh
bash plugins/trim-output/tests/run.sh
bash plugins/trim-output/tests/filter.sh
bash plugins/delegation/tests/provider.sh
bash plugins/delegation/tests/run.sh
bash plugins/delegation/tests/log.sh
bash plugins/delegation/tests/note.sh
bash plugins/delegation/tests/config.sh
bash plugins/delegation/tests/agents.sh
```

CI (`.github/workflows/ci.yml`) runs the hook suites plus JSON validation, ShellCheck, and a marketplace integrity check on every push to `main` and on pull requests.

## License

[MIT](LICENSE) © levonn-dev
