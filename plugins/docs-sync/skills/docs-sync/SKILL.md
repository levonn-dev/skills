---
name: docs-sync
description: Use at the end of any task that changed code, config, schemas, infrastructure, or made a notable decision. Check whether documentation describing the change needs updating, update it in the same task, or state explicitly that none applies.
---

# Docs Sync

Documentation drifts when it is treated as a separate, later task. Fold it into the task that caused the change, so it never needs a follow-up reminder.

## When to run

- After any code change.
- After non-code changes too: config, schemas, environment variables, infrastructure, build or CI, CLI flags, data formats, runbooks.
- After a notable design or process decision, even when no files changed.

## What to do

- Identify docs that describe the thing you changed:
  - README, `docs/`, CHANGELOG.
  - API specs (OpenAPI/Swagger), generated reference docs.
  - Inline docstrings and comments next to the changed code.
  - ADRs, runbooks, `AGENTS.md` / `CLAUDE.md`.
- Update them in the same task, matching the actual new behavior.
- If nothing needs updating, say so explicitly. "Checked docs, none affected" is a valid and expected outcome. Silence is not.

## Note on the Stop hook

A `Stop` hook ships with this plugin. When a turn ends with on-disk changes but no doc files were touched, it asks you to confirm or update docs before stopping. The hook is a safety net for file changes it can see in `git`. This guidance is broader: it also covers non-code work and decisions that leave no diff, which the hook cannot detect.
