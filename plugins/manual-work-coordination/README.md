# manual-work-coordination

Get out of the way cleanly when the user takes part of a task by hand, and pick back up without trampling what they did.

## What ships

- `skills/manual-work-coordination/SKILL.md`: the handoff protocol. Recognize the trigger phrases ("pause", "I'll do X myself", "I'll verify"); finish only the smallest safe unit and stop; state exactly where you stopped; on resume, trust the manual work instead of redoing, reverting, or re-verifying it.

Skill only; no hooks or commands.

## Install

```
/plugin install manual-work-coordination@levonn-dev-skills
```

Disable per project in `<repo>/.claude/settings.local.json`:

```json
{ "enabledPlugins": { "manual-work-coordination@levonn-dev-skills": false } }
```
