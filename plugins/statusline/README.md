# statusline

A Claude Code status line, installed once and kept current by the plugin.

Line layout: model, effort level, a 20-segment context bar with token counts, output style (when not default), then kubectl context/namespace (when kubectl is present), the working directory, and the git branch with dirty bits (`!` modified, `-` deleted, `?` untracked, `+` added, `>` renamed, `*` ahead, `x` behind).

## Wrapping

Claude Code sets `COLUMNS` for the script on every run. Sections are packed in order onto as many lines as they need: a section that would overrun the width, minus a two-column margin, starts a new line, and a section wider than the screen sits alone on its own line. The bar with its total and the base/chat split are separate sections, so a narrow screen keeps the bar on the first line and moves the split down. Without `COLUMNS` everything stays on one line. Widths are counted in characters, so the locale must be UTF-8 for the block glyphs to count as one column each.

## Context section

```
█████████▒▒▒▒▒▒▒▒▒▒▒ 91k/200k 46%  base 45k 22%  chat 47k 23%
```

- Tokens come before every percentage: used over window size, then the split.
- `base` is everything present on the first turn: system prompt, tool and MCP definitions, memory, CLAUDE.md, hook context, first prompt. `chat` is everything added since. After a compaction, base restarts at the first turn after the boundary.
- The bar is stacked: base segments in blue-grey, chat segments in the green-to-red gradient, unused segments dark grey. The words take the same colors, `chat` matching the last filled segment. The model name is teal so it does not blend with the base segments.
- The status line payload only carries totals, so base is read from the transcript file the payload names. It is cached per session in `${TMPDIR:-/tmp}/statusline-base.<session id>` together with the transcript size scanned so far; a refresh only greps the bytes appended since for a compaction marker and re-reads the whole transcript when it finds one. Without a transcript or before the first reply, only `used/size %` shows. Before any usage at all, `--`.
- The per-type breakdown `/context` prints (system prompt, MCP tools, skills, messages) is not exposed to status line scripts, so it cannot be shown here.

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
bash plugins/statusline/tests/render.sh
```

`run.sh` runs the sync hook against temp files for each target state: missing, unmarked, marked and stale, marked and identical, source missing. `render.sh` feeds synthetic payloads and transcripts through the script, with the cache pointed at a temp dir via `STATUSLINE_CACHE_DIR`, and checks the context label, bar, colors, and wrapping: split, compaction rebase, missing transcript, no reply yet, chat clamped at zero, no usage, boundary without a reply, cache written, cached base used, growth keeps the cache, compaction invalidates it, word colors, one line when wide or without `COLUMNS`, wrapped lines within the width, oversized section alone.
