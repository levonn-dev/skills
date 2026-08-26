# docs-sync

Documentation updates ride the change that caused them, never a later task.

## What ships

- `skills/docs-sync/SKILL.md`: when to check and what counts as documentation: README and `docs/`, API specs, request collections (Bruno, Postman, `.http`), test scripts and end-to-end flows that exercise the changed surface, observability artifacts (runbooks, dashboards, alert rules and their runbook anchors, index pages), inline docstrings, ADRs, `AGENTS.md` / `CLAUDE.md`. "Checked docs, none affected" is an expected outcome; silence is not.
- `hooks/check-docs.sh`: a `Stop` hook. When a turn ends with substantive on-disk changes (per `git status`) but no documentation file was touched, it blocks the stop once and asks for a docs check. Loop-safe (`stop_hook_active` lets the follow-up turn stop), read-only git, fails open without `jq` or outside a repo. Lockfiles alone never trigger it.

The hook only sees files; the skill also covers decisions and non-code work that leave no diff.

## Install

```
/plugin install docs-sync@levonn-dev-skills
```

Disable per project in `<repo>/.claude/settings.local.json`:

```json
{ "enabledPlugins": { "docs-sync@levonn-dev-skills": false } }
```

## Tests

```
bash plugins/docs-sync/tests/run.sh
```

Each `tests/cases/*.json` file supplies a `git status --porcelain` fixture and an expected decision. The hook reads fixtures through the `DOCS_SYNC_TEST` / `DOCS_SYNC_TEST_STATUS` seam, so the suite never touches a real repo.
