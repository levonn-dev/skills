---
description: Install the plugin's status line script as ~/.claude/statusline-command.sh and point statusLine in ~/.claude/settings.json at it; later plugin updates sync automatically at session start
---

Install the managed status line:

1. Locate the plugin's script at `${CLAUDE_PLUGIN_ROOT}/bin/statusline.sh`. If that path does not resolve, use the newest `~/.claude/plugins/cache/levonn-dev-skills/statusline/*/bin/statusline.sh`.
2. If `~/.claude/statusline-command.sh` exists and does not contain the line `managed by statusline@levonn-dev-skills`, it is a hand-written status line. Show its first ten lines and stop; the user decides whether to replace it. Never overwrite it without their answer.
3. Copy the script to `~/.claude/statusline-command.sh` and make it executable.
4. In `~/.claude/settings.json`, set `statusLine` to `{"type": "command", "command": "bash ~/.claude/statusline-command.sh"}`, preserving every other key (read with `jq`, write the merged result; create the file with just that key if it is missing). Show the before and after of the `statusLine` key only.
5. Reply with the paths written and note that the status line renders on the next update and that plugin updates now sync to it at session start via the plugin's `SessionStart` hook. The script needs `jq` and `git`; `kubectl` is optional.
