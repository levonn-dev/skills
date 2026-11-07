---
name: delegation
description: Use before dispatching subagents, or when a task has several independent parts: when a subagent pays off, waves versus chains, orchestrator subagents for dependent work, which delegation agent fits, model and effort choice, and report size.
---

# Delegation

Apply before dispatching a subagent, or when a task splits into several parts.

## When a subagent pays off

- Parallel independent work.
- Noisy output the conversation does not need again.
- A reviewer that has not seen how the code was written.
- A task that needs fewer tools than the main conversation has.

## When it does not

- Work finishable in a handful of tool calls.
- Checking the conversation's own work.
- One dependent chain that fits in context.

## Which agent

- `delegation:explorer`: where things are across a repository. Read-only. Haiku.
- `delegation:reader`: one question over large files or logs. Haiku.
- `delegation:test-runner`: a noisy command, reported as failures and summary. Haiku.
- `delegation:researcher`: a digest of web documentation with sources. Sonnet.
- `delegation:implementer`: a fully specified change that can run in parallel. Sonnet.
- `delegation:reviewer`: fresh eyes on a diff. Sonnet, high effort.

## Waves versus chains

- Send independent subtasks out in one parallel wave, so the main conversation resumes once.
- Run dependent subtasks inside one orchestrator subagent that returns once.
- Never run a sequence of main-thread dispatches separated by long runs when the main cache lasts five minutes. Every resumption re-reads the whole context cold.

## The hand-off

- State the goal and what is already ruled out.
- Name the files to read instead of retyping them.
- Keep the scope explicit and narrow.
- Say what report shape you want back.
- Give the check that defines done.

## Model and effort ladder

- Cheapest tier: transcription from complete code and single-file mechanical fixes.
- Mid tier as the floor: reviewers and implementers working from a prose spec.
- The main model: design judgment.
- Pass `model` explicitly when it matters. The pin hook fills blanks from the machine's config or the defaults.

## Report size

- Keep reports under about 2,000 tokens.
- Artifacts, long output, and file bodies go to files. The report carries the path.

## Gotchas

- A fresh subagent never reads the parent's cache and starts at 13k to 47k tokens.
- Its own cache lives five minutes unless its agent file sets an hour. The delegation agents set an hour.
- A fork shares the parent's cache but carries the whole context and runs on the parent model.
- Aliases resolve to older models off the Anthropic API. `/delegation:configure` is for that.

## Measurement

- `/usage` shows attribution per subagent.
- `/delegation:report` summarizes the delegation log.
