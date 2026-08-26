# statusline

A single-line Claude Code status line, installed once and kept current by the plugin.

Line layout: model, effort level, a 20-segment context-used bar with percentage, output style (when not default), then kubectl context/namespace (when kubectl is present), the working directory, and the git branch with dirty bits (`!` modified, `-` deleted, `?` untracked, `+` added, `>` renamed, `*` ahead, `x` behind).

## What ships

- `bin/statusline.sh`: the script. Its second line is a marker (`managed by statusline@levonn-dev-skills`) that tells the sync hook it owns the installed copy. Needs `jq` and `git`; `kubectl` is optional.
- `commands/install.md`: `/statusline:install`. Copies the script to `~/.claude/statusline-command.sh` and sets `statusLine` in `~/.claude/settings.json` to run it, preserving other settings. Refuses to overwrite an existing status line that lacks the marker until the user says so.
- `hooks/sync-statusline.sh`: a `SessionStart` hook. When the installed copy carries the marker and differs from the plugin's script, it is overwritten, so a plugin update reaches the status line on the next session. A missing target (install not run) or an unmarked target (hand-written) is never touched. Silent, always exit 0.

A plugin cannot set `statusLine` itself; that key lives in the user's settings, which is why install is a command and updates are a hook.

## Install

```
/plugin install statusline@levonn-dev-skills
/statusline:install
```

To stop the sync without uninstalling, delete the marker line from `~/.claude/statusline-command.sh`; the hook then treats it as hand-written.

## Tests

```
bash plugins/statusline/tests/run.sh
```

Runs the sync hook against temp files for each target state: missing, unmarked, marked and stale, marked and identical, source missing.
