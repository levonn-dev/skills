#!/usr/bin/env bash
# statusline: SessionStart hook. Copies the plugin's status line script over the
# installed one when they differ, so a plugin update reaches the status line on
# the next session. Only touches a target that carries the plugin's marker line;
# a missing or hand-written target is left alone. Silent: SessionStart stdout
# becomes session context.

set -uo pipefail

source="${CLAUDE_PLUGIN_ROOT:-}/bin/statusline.sh"
target="${STATUSLINE_TARGET:-$HOME/.claude/statusline-command.sh}"
marker='managed by statusline@levonn-dev-skills'

[ -f "$source" ] || exit 0
[ -f "$target" ] || exit 0
grep -q "$marker" "$target" 2>/dev/null || exit 0
cmp -s "$source" "$target" && exit 0

cp "$source" "$target" 2>/dev/null
exit 0
