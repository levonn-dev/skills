---
name: coding-guidelines
description: Use when writing, reviewing, or refactoring code. Enforces stating assumptions before acting, writing the minimum code that solves the problem, changing only what the task requires, and defining a verifiable success check before claiming done.
---

# Coding Guidelines

Themes 1 to 4 restate principles Andrej Karpathy stated about common LLM coding failure modes. Themes 5 and 6 are project-specific additions. Apply when writing, reviewing, or refactoring code. Use judgment for trivial scripts. These rules target high-stakes code where mistakes compound.

## 1. Surface what you don't know

- State assumptions out loud before acting.
- When a request is ambiguous, present the alternative interpretations rather than silently choosing one.
- Ask one focused question instead of guessing.
- Don't hide confusion behind plausible-looking output. The fastest path to a wrong answer is pretending the question was clear.

## 2. Write the minimum that works

- No speculative features.
- No error handling for impossible states.
- No flexibility nobody asked for.
- Three similar lines beat a premature framework.
- Build abstractions only when:
  - (a) the current task requires them, or
  - (b) the user explicitly names a future use case to design for.
- A senior reviewer should not look at the diff and say "this is doing too much."

## 3. Stay in your lane

- Touch only the lines the task requires.
- Don't tidy unrelated code.
- Don't rename for taste.
- Don't delete pre-existing dead code as a side effect.
- Every changed line should trace back to the request. Cleanups that weren't requested are noise that hides the actual change.

## 4. Define done before starting

- Turn a vague task into a concrete check: a command to run, a test to pass, a behavior to observe.
- Loop until the check passes.
- "Looks right" is not a finish line. Verification is.
- If you can't define a check, you don't yet understand the task.

## 5. Keep files small and focused

- Prefer many small, focused files over a few sprawling ones.
- Never propose putting "everything in one file." It is hostile to maintenance.
- When a file grows hard to navigate, suggest splitting it along natural seams: by responsibility, feature, screen, or layer.
- Follow the project's existing module boundaries. Don't invent a new structure mid-task.

## 6. Use the project's own tooling

- Before running a build, test, run, lint, or format command directly, check for a task runner: Taskfile, justfile, Makefile, npm/pnpm scripts, Rakefile, Maven/Gradle wrappers, etc.
- If one exists with a matching target, use it instead of invoking the underlying tool (mvn, gradle, go, npm, cargo, pytest, etc.) by hand.
- The task runner encodes flags, environment, and ordering that the raw command omits. Bypassing it produces results that don't match how the project actually builds and runs.
- Fall back to the raw tool only when no target covers what you need, and say why you are bypassing the runner.
