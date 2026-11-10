# git-safety

Keeps repo state changes in the user's hands. Claude reads git freely, never writes it, and hands commits back as a queue the user replays.

## What ships

- `skills/git-safety/SKILL.md`: the advisory skill. Lists what is allowed (read-only subcommands, list/show/get modes), what is blocked, and how to refuse a write request.
- `hooks/block-git-writes.sh`: a `PreToolUse` hook on `Bash` that hard-denies any git command that modifies local or remote state. Handles chained commands, subshells, `-C`, env prefixes, and quoted heredocs (which are allowed). A quoted plain word is read as the shell reads it, so `git "commit"` and `"git" commit` deny. A substitution inside double quotes is scanned as a command of its own, so `out="$(git push)"` denies. A comment is skipped: one that names a write passes, and an apostrophe in one hides nothing after it. A lone-key config read passes, `git config --global user.name 2>/dev/null` included. `git clone` passes in one shape only, `git clone [flags] <repository> <absolute target>` with the target outside every git repository, since such a clone changes no existing repository. Both are read strictly, plain tokens and plain redirections only, so an expansion, a substitution or a continued line that could hide an argument from the hook denies. Exit 2 denies; exit 0 allows.
- `commands/commit-queue.md`: `/git-safety:commit-queue [hints]`. Partitions the working tree into commits (every changed file in exactly one commit, final-state replay, dependency order, generated code with its source, tests and docs with the change they belong to), verifies the partition against `git status` for duplicates and gaps, and emits separate single-line `git add ... && git commit -m ...` commands plus a `commit-queue.sh` the user can run.

## Why separate single-line commands

A multi-line `&& \` chain pasted into a terminal can corrupt one subject or drop one line while the rest still runs, leaving a partial replay that looks complete. One line per commit fails loudly and is easy to check against `git log --oneline`.

## Install

```
/plugin install git-safety@levonn-dev-skills
```

The hook needs `jq`, bash 3.2 or later, and awk. It uses no GNU-only tools, so the stock macOS ones will do. Without `jq` it denies every Bash command, so the gap shows instead of commands passing unread.

Disable per project in `<repo>/.claude/settings.local.json`:

```json
{ "enabledPlugins": { "git-safety@levonn-dev-skills": false } }
```

## Tests

```
bash plugins/git-safety/tests/run.sh
```

Each `tests/cases/*.json` file is piped through the hook; the filename prefix (`allow_` or `block_`) is the expected outcome. `__FIX__` in a case stands for a fixture directory the runner builds, holding a working tree, a bare git dir, a symlink into the tree and a plain directory. The runner also builds one 200,000-character command with a write at its end, which must deny within 10 seconds.
