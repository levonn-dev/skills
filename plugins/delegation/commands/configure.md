---
description: Choose which model alias each subagent type is pinned to on this machine, map aliases to model ids, and optionally set the one-hour prompt cache lifetime in user settings
---

Configure subagent model pins:

1. Run `${CLAUDE_PLUGIN_ROOT}/bin/config.sh show` and `${CLAUDE_PLUGIN_ROOT}/bin/config.sh propose`. Present the provider, the alias table, and the proposal as one table with a `resolves to` column. State once that on a session whose main model is already the cheap one, `inherit` is the right answer for that role. The resolves-to column reflects any alias map active in this session.
2. AskUserQuestion: accept the proposal, adjust roles, or set everything to `inherit`. When adjusting, ask per role with the options `haiku`, `sonnet`, `opus`, `inherit`. Offer `fable` through the free-text option, noting it is Fable 5.1 on the Anthropic API and unlisted elsewhere.
3. AskUserQuestion: any other subagent types to pin, as `type=alias` pairs. The default is none.
4. Run `${CLAUDE_PLUGIN_ROOT}/bin/config.sh write` with every `type=alias` pair collected. Show the before and after.
5. Run `${CLAUDE_PLUGIN_ROOT}/bin/alias-map.sh show`. Present one table: alias, user value, managed source, session value. Explain in two lines: pins are aliases because the Agent tool accepts nothing else in `model`, and what an alias means on this machine is `ANTHROPIC_DEFAULT_<ALIAS>_MODEL` in user settings, which also changes the main session's alias and, for `haiku`, background tasks. Then AskUserQuestion: map any alias to a model id, as `alias=id` pairs through the free-text option, any token without whitespace, for example a Bedrock inference profile id or a dated Anthropic id. The default is to keep the current values. Name the aliases that are managed and cannot be set here.
   - On pairs, run `${CLAUDE_PLUGIN_ROOT}/bin/alias-map.sh set` with them and show the before and after. Add one sentence: the settings value overrides a shell export of the same variable in most sessions, so if a later session's `session` value still differs from `user`, remove the export from the shell profile.
6. Run `${CLAUDE_PLUGIN_ROOT}/bin/cache-ttl.sh show`.
   - If `eligible: yes`, explain in two lines that the one-hour lifetime costs 2x on cache writes instead of 1.25x and pays back when turns are often five minutes to an hour apart. Then AskUserQuestion whether to set both keys to `1h` in user settings. On yes, run `${CLAUDE_PLUGIN_ROOT}/bin/cache-ttl.sh set 1h` and show its output.
   - If `eligible: no`, say which key is managed or which variable forces the value, and skip the question.
7. Reply with the paths written. Say that pins apply on the next Agent call, the alias map and the cache lifetime on the next session, and that `/delegation:report` confirms pins are firing.
