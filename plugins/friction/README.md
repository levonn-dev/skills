# friction

Log the small things that get in the way while working, in the moment, so they add up to a picture of where a project needs sanding down. Then sand it down.

## What ships

- `skills/friction/SKILL.md`: what counts (retried tool calls, undocumented setup, flaky or slow commands, stale state, misleading errors, gotchas), what does not (real bugs, accomplishments, style opinions), and the entry format: one bullet in `FRICTION.md` at the project root, `- YYYY-MM-DD [model]: what I was doing, what got in the way. Optional guess at cause or fix.`
- `hooks/load-friction.sh`: a `SessionStart` hook that injects the skill body as session context, so logging happens proactively without the skill being invoked.
- `commands/find.md`: `/friction:find`. Re-reads the session, dedupes against `FRICTION.md`, and appends anything unlogged.
- `commands/review.md`: `/friction:review [filter]`. Groups the open entries by root cause and proposes an outcome per group: fix (small in-repo change with a named check), track (real work, goes to its own task), outside (cause is a tool, the harness, or the machine; the user gets the action), or drop (one-off or already gone). Stops for approval, then applies the fixes with docs updated in the same change, and removes resolved entries

Both commands are user-triggered. In-the-moment logging never fixes anything; the fix is a deliberate `/friction:review` pass.

## Install

```
/plugin install friction@levonn-dev-skills
```

Disable per project in `<repo>/.claude/settings.local.json`:

```json
{ "enabledPlugins": { "friction@levonn-dev-skills": false } }
```
