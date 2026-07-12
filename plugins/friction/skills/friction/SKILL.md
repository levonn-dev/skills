---
name: friction
description: "Use when you hit a small friction while working: a retried tool call, a confusing or undocumented setup step, a flaky command, a stale cache, a misleading error, a non-obvious gotcha. Log it to FRICTION.md in one or two sentences, in the moment, then move on."
---

# Friction

When something small gets in your way while working, log it to `FRICTION.md` at the project root. None of these are blocking on their own. Logged together they show where the project needs sanding down.

## What counts

- A tool call or command that missed and had to be retried
- A confusing or undocumented setup step
- A flaky or slow command
- A stale cache or state that had to be cleared
- A misleading error message
- A non-obvious gotcha you had to discover

## What does not count

- Real bugs in the code you are working on: that is the task, or tracked work
- Things you accomplished: that is a changelog, not a friction log
- Style opinions with no incident behind them

## How to log

- Append one bullet to `FRICTION.md` in the moment, then get back to the task
- Create the file with a `# Friction log` heading if it does not exist
- Format: `- YYYY-MM-DD [model]: what I was doing, what got in the way. Optional guess at cause or fix.`
- One or two sentences. Do not fix the friction unprompted.
- Log proactively. Do not wait for the user to ask.

## Review pass

- `/friction:review` scans the session so far for unlogged frictions, dedupes against existing entries, and appends them
- User-triggered only. Never run a review sweep unprompted.
