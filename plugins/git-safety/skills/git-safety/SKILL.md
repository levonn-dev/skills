---
name: git-safety
description: Use whenever git operations are involved. Forbids running git commands that modify local or remote repo state (commit, push, pull, merge, rebase, reset, checkout, branch -d, tag, config, worktree, etc.). Read-only git is fine. If the user wants a state change, ask them to run it themselves.
---

# Git Safety

A `PreToolUse` hook ships with this plugin and will hard-deny any git command that modifies repo state, local or remote. Attempting to run one only burns a turn and returns a deny message. **Don't try.** Ask the user to run it themselves.

## What you may run

Always-allowed read-only git subcommands:

- `status`, `log`, `diff`, `show`, `blame`
- `ls-files`, `ls-tree`, `ls-remote`
- `rev-parse`, `rev-list`, `describe`, `name-rev`
- `cat-file`, `count-objects`, `grep`, `shortlog`, `whatchanged`
- `help`, `version`, `var`
- `for-each-ref`, `check-ref-format`, `check-ignore`, `check-attr`, `check-mailmap`
- `verify-commit`, `verify-tag`, `verify-pack`
- `merge-base`, `merge-tree`

Conditional subcommands, allowed only in list/show/get mode:

- `git branch` (no args, or with `-l` / `--list`)
- `git tag` (no args, or with `-l` / `--list`)
- `git remote` (no args, or with `-v`, `show`, `get-url`)
- `git stash list`, `git stash show`
- `git config --get`, `git config --get-all`, `git config -l`, or a lone key with no value such as `git config --global user.name`
- `git submodule status`, `git submodule foreach`, `git submodule summary`
- `git notes list`, `git notes show`
- `git reflog`, `git reflog show`, `git reflog exists`

One write is allowed because it touches no existing repository:

- `git clone [flags] <repository> <absolute target>`, when the target is outside every git repository. Spell the target as a plain absolute path such as `/tmp/name`: no `~`, no variable, no quotes, no `..`. The flags that pass are `--depth`, `-b`/`--branch`, `--filter`, `-j`/`--jobs`, `-q`, `-v`, `--progress`, `-n`, `--bare`, `--mirror`, `--single-branch`, `--no-tags`, `--recurse-submodules`, `--shallow-submodules` and `--sparse`.

Write a lone-key config read or a clone with plain arguments only: no quotes, variables, globs, braces, substitutions or line continuations, and no `GIT_` variable anywhere in a clone command. A plain redirection such as `2>/dev/null` is fine. Anything the hook cannot read with certainty is denied.

## What gets blocked

Anything that writes:

- Commit operations: `commit`, `add`, `rm`, `mv`
- Remote sync: `push`, `pull`, `fetch`
- Clone into a repository: `clone` with no target, a relative target, a target inside any working tree or git dir, a global flag before `clone`, or any flag not listed above
- History rewrites: `merge`, `rebase`, `reset`, `restore`, `revert`, `cherry-pick`
- Working tree changes: `checkout`, `switch`, `clean`
- Branch/tag writes: `branch -d`/`-D`/`-m`, `tag <new>`
- Config writes: `config <key> <val>`, `config --add`, `config --unset`
- Stash writes: `stash push`/`pop`/`drop`/`clear`
- Worktree writes: `worktree add`/`remove`
- Submodule writes: `submodule add`/`update`/`init`/`deinit`
- Note writes: `notes add`/`append`/`copy`/`edit`/`remove`
- Reflog writes: `reflog expire`/`delete`
- Other: `send-email`, `format-patch` (file mode), `filter-branch`, `gc`, `prune`, `repack`, `pack-refs`, `update-ref`, `update-index`, `write-tree`, `replace`

## When the user asks for a write

Refuse with this phrasing:

> I won't run `<command>`. It modifies repo state. Please run it yourself if that's what you want.

Then, if helpful:

- Describe what the command would do.
- Explain why the user might want it.
- Do not retry.

## When the user wants commits

Accumulate rather than refuse and stop: build the commit commands and hand them over. `/git-safety:commit-queue` does this for the whole working tree: every changed file in exactly one commit, partition verified against `git status`, single-line commands the user replays. Use it at review checkpoints and whenever implementation work leaves a multi-commit tree behind.
