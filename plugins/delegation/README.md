# delegation

Subagents that name no model run on whatever the session runs on, which is usually the most expensive choice for reading, searching, and test-running work. This plugin fills in a cheaper model alias on those dispatches through a `PreToolUse` hook on Agent, keyed to the subagent type and to the provider the session runs on. It also ships six delegation agents, a `SessionStart` note about cache lifetimes, a `PostToolUse` log of every subagent run, `/delegation:configure` to set pins once per machine, and `/delegation:report` to see what each subagent ran on.

## Pin rules

The hook applies these in order and stops at the first that matches:

1. `CLAUDE_DELEGATION_NO_PIN=1` leaves everything alone.
2. A dispatch that names a model is untouched.
3. If `CLAUDE_CODE_SUBAGENT_MODEL` or `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` is set, the hook stands down.
4. `fork` is never pinned.
5. With a config file for the detected provider, its `pins` apply. `inherit` or a type missing from `pins` means untouched.
6. Without one, the defaults apply, and only on the Anthropic API:
   - `Explore` to `haiku`
   - `general-purpose` or an absent type to `sonnet`
   - everything else untouched

A config made for a different provider than the one detected is ignored, so the defaults rule applies instead.

Pins are injected as per-call aliases. Aliases are the only values the Agent tool accepts in `model`. What each alias means on a machine is set by `ANTHROPIC_DEFAULT_<ALIAS>_MODEL` for `haiku`, `sonnet`, `opus`, and `fable`, which `/delegation:configure` can write. Without a map, on the Anthropic API the aliases mean the 5.5 models, and off it they mean older models: Sonnet 4.5 and Haiku 4.5 on Bedrock and Vertex, Opus 4.6 on Foundry.

### Provider detection

The provider comes from `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`, `CLAUDE_CODE_USE_FOUNDRY`, `CLAUDE_CODE_USE_ANTHROPIC_AWS`, `CLAUDE_CODE_USE_MANTLE`, and `ANTHROPIC_BASE_URL`. A Claude apps gateway has no marker and is detected as `anthropic`.

With `ANTHROPIC_BASE_URL` set (an LLM gateway), the provider is `gateway`. The defaults do not apply there, and `/delegation:configure` proposes `inherit` for every role.

## /delegation:configure

Writes the per-machine pins to `${CLAUDE_CONFIG_DIR:-~/.claude}/delegation.json`.

- Shows the detected provider, what each alias resolves to there, and a proposed pin for every role.
- Asks whether to accept the proposal, adjust roles (`haiku`, `sonnet`, `opus`, `inherit`, or `fable` as free text), or set everything to `inherit`.
- Asks for any other subagent types to pin, as `type=alias` pairs.
- Writes the file and shows before and after. Re-running starts from the existing choices.
- Alias-map step: shows what each alias resolves to on this machine (user settings value, managed source, this session's value) and offers to map any alias to a model id, as `alias=id` pairs, written to `ANTHROPIC_DEFAULT_<ALIAS>_MODEL` in the `env` block of user settings. Any token without whitespace is accepted and passed through verbatim. A managed alias is skipped. The map also changes the main session's alias and, for `haiku`, background tasks.
- Cache-lifetime step: offers to set `promptCacheTtl` and `subagentPromptCacheTtl` to `1h` in user settings only. It offers this only when neither key is managed on disk and `FORCE_PROMPT_CACHING_5M` is unset, and writes only after you say yes. It refuses to touch a `settings.json` that is not a single JSON object.

Pins apply on the next Agent call. The alias map and the cache lifetime apply on the next session.

### First run

On the first new session on a machine with no config, the `SessionStart` hook shows a one-line notice to run `/delegation:configure`. It shows once per detected provider, so a machine that moves to another provider gets one more notice. The marker lives in `CLAUDE_PLUGIN_DATA`, or in `~/.claude/delegation/` on builds without it, and is written before the notice, so an unwritable location means silence rather than a repeat. Resumed, cleared, compacted, and forked sessions never show it. The notice is for you and costs no context.

## /delegation:report

Prints a table of the most recent session's subagent runs (the most recently modified log file): time, type, requested model, resolved model, duration, tool count, final context size, and output tokens, with totals. `--all` reads every session logged today. A last line counts the pins that fired, by type and alias, split into config and default sources.

- Per-subagent token figures are the final request only, not whole-run spend.
- The pins line is how you confirm pins fire on a given machine.

## Agents

| Agent | Model | Effort | Tools | CLAUDE.md loaded | Returns |
|---|---|---|---|---|---|
| `explorer` | haiku | low | Read, Glob, Grep | no | `file:line` findings, never file contents |
| `reader` | haiku | low | Read, Grep, Bash | no | the answer to one question about large files or logs |
| `test-runner` | haiku | low | Bash, Read, Grep | no | failures and the summary of a noisy command |
| `researcher` | sonnet | medium | WebFetch, WebSearch, Read | no | a sourced digest of external documentation |
| `implementer` | sonnet | medium | Read, Edit, Write, Glob, Grep, Bash | yes | a fully specified change, done and checked |
| `reviewer` | sonnet | high | Read, Glob, Grep, Bash | yes | a fresh-eyes review of a diff or branch |

## Limitations

- A pin is an alias, never a model id. The Agent tool's `model` field is an enum of aliases and Claude Code re-validates a hook's rewritten input against it (verified on 2.1.319). Map an alias to a model id with the alias-map step instead; four distinct models per machine is the ceiling. Without a map, aliases resolve to older models off the Anthropic API (see above).
- A Claude apps gateway is detected as `anthropic`, so defaults and Anthropic-API aliases are assumed there.
- On a `gateway` provider (`ANTHROPIC_BASE_URL` set) the defaults do not apply and no alias is assumed to resolve to a known model; pins take effect only from a config file.
- The hook cannot see the main model. On a Haiku main session a `sonnet` pin moves work up. Choose `inherit` for that role in `/delegation:configure`.
- Model pinning has been intermittently broken in some Claude Code builds. The report shows the resolved model, so you can tell.
- A background Agent dispatch returns `status: async_launched` with no duration or usage, so it appears as a row of dashes and its completion is never logged.

## Escape hatch

`CLAUDE_DELEGATION_NO_PIN=1` turns pinning off. The log, the agents, and the report keep working.

## What ships

- `hooks/hooks.json`: registers the three hooks.
- `hooks/pin-subagent-model.sh`: `PreToolUse` on Agent, the pin rules above.
- `hooks/log-subagent.sh`: `PostToolUse` on Agent, logs each run.
- `hooks/session-note.sh`: `SessionStart`, adds a short delegation note to context and shows the first-run notice.
- `agents/`: the six agents.
- `skills/delegation/SKILL.md`: when and how to delegate.
- `commands/configure.md` and `commands/report.md`: the two slash commands.
- `bin/provider.sh` and `bin/settings.sh`: provider detection, path helpers, and user-settings helpers, sourced by the others.
- `bin/config.sh`, `bin/alias-map.sh`, `bin/cache-ttl.sh`, `bin/report.sh`: the scripts behind the commands. Need `jq`.

Every script runs under `#!/usr/bin/env bash` and works on bash 3.2, the one macOS ships, so no newer bash is needed and the login shell does not matter. The hooks do nothing without `jq`; the scripts behind the commands fail with a `jq` error.

## Install

```
/plugin install delegation@levonn-dev-skills
/delegation:configure
```

## Tests

```
bash plugins/delegation/tests/provider.sh
bash plugins/delegation/tests/run.sh
bash plugins/delegation/tests/log.sh
bash plugins/delegation/tests/note.sh
bash plugins/delegation/tests/config.sh
bash plugins/delegation/tests/alias-map.sh
bash plugins/delegation/tests/agents.sh
```

`provider.sh` checks provider detection. `run.sh` feeds hook payloads through the pin hook. `log.sh` checks the run log. `note.sh` checks the session note and the first-run notice. `config.sh` checks the config and cache-lifetime scripts, and that `bin/` and `hooks/` stay free of bash 4 constructs. `alias-map.sh` checks the alias-map script. `agents.sh` checks the agent frontmatter and the description footprint.
