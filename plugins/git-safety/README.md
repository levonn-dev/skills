# git-safety

Keeps repo state changes in the user's hands. Claude reads git freely, never writes it, and hands commits back as a queue the user replays.

## What ships

- `skills/git-safety/SKILL.md`: the advisory skill. Lists what is allowed (read-only subcommands, list/show/get modes), what is blocked, and how to refuse a write request.
- `hooks/block-git-writes.sh`: a `PreToolUse` hook on `Bash` that hard-denies any git command that modifies local or remote state. Handles chained commands, subshells, `-C`, env prefixes, and quoted heredocs (which are allowed). Exit 2 denies; exit 0 allows.
- `commands/commit-queue.md`: `/git-safety:commit-queue [hints]`. Partitions the working tree into commits (every changed file in exactly one commit, final-state replay, dependency order, generated code with its source, tests and docs with the change they belong to), verifies the partition against `git status` for duplicates and gaps, and emits separate single-line `git add ... && git commit -m ...` commands plus a `commit-queue.sh` the user can run.

## Why separate single-line commands

A multi-line `&& \` chain pasted into a terminal can corrupt one subject or drop one line while the rest still runs, leaving a partial replay that looks complete. One line per commit fails loudly and is easy to check against `git log --oneline`.

## Install

```
/plugin install git-safety@levonn-dev-skills
```

Disable per project in `<repo>/.claude/settings.local.json`:

```json
{ "enabledPlugins": { "git-safety@levonn-dev-skills": false } }
```

## Tests

```
bash plugins/git-safety/tests/run.sh
```

Each `tests/cases/*.json` file is piped through the hook; the filename prefix (`allow_` or `block_`) is the expected outcome.
