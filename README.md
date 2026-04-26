# levonn-dev-skills

Personal Claude Code plugin marketplace.

## Plugins

- **coding-guidelines** — behavioral guidelines for clean, surgical, goal-driven coding.
- **git-safety** — advisory skill + `PreToolUse` hook that hard-denies git write commands. Read-only git is unaffected.

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

## Tests

```
bash plugins/git-safety/tests/run.sh
```
