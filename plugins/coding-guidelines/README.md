# coding-guidelines

Behavioral guidelines for clean, surgical, goal-driven coding, injected into every session.

## What ships

- `skills/coding-guidelines/SKILL.md`: the guidelines, eight themes. Surface what you don't know; write the minimum that works; stay in your lane; define done before starting; keep files small; use the project's own tooling; write for the maintainer (terse comments, shipped files free of process references); triage review findings as fix-now or decline-with-reason.
- `hooks/load-guidelines.sh`: a `SessionStart` hook that strips the skill's frontmatter and injects the body as session context, so the rules apply without the skill being invoked. The SKILL.md is the single source of truth.
- `agents/finding-verifier.md`: adversarial verifier for review findings. Refute-by-default: a finding drives an edit only after it comes back CONFIRMED with file:line evidence and a concrete failure scenario. Run one per finding before a fix pass.

## Install

```
/plugin install coding-guidelines@levonn-dev-skills
```

Disable per project in `<repo>/.claude/settings.local.json`:

```json
{ "enabledPlugins": { "coding-guidelines@levonn-dev-skills": false } }
```
