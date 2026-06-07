# levonn-dev-skills

Personal Claude Code plugin marketplace.

## Plugins

- **coding-guidelines** — behavioral guidelines for clean, surgical, goal-driven coding.
- **git-safety** — advisory skill + `PreToolUse` hook that hard-denies git write commands. Read-only git is unaffected.
- **manual-work-coordination** — guidance to stop cleanly when you take a task over by hand, and to trust your manual work on resume instead of redoing or re-verifying it.
- **docs-sync** — skill + `Stop` hook that reminds you to update relevant documentation after code and non-code changes. The hook nudges when a turn ends with file changes but no docs touched; read-only git, loop-safe.

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
```

CI (`.github/workflows/ci.yml`) runs both suites plus JSON validation, ShellCheck, and a marketplace integrity check on every push to `main` and on pull requests.

## License

[MIT](LICENSE) © levonn-dev
