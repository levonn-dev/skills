---
name: coding-guidelines
description: Use when writing, reviewing, or refactoring code, and when triaging review findings. Enforces stating assumptions before acting, writing the minimum code that solves the problem, changing only what the task requires, defining a verifiable success check before claiming done, keeping shipped files free of process references, and fixing verified findings in the change that surfaces them.
---

# Coding Guidelines

Themes 1 to 4 restate principles Andrej Karpathy stated about common LLM coding failure modes. Themes 5 to 8 are additions from practice. Apply when writing, reviewing, or refactoring code.

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
- Follow the existing patterns within a file and code base. Consistency matters.
- Every changed line should trace back to the request. Cleanups that weren't requested are noise that hides the actual change.

## 4. Define done before starting

- Turn a vague task into a concrete check: a command to run, a test to pass, a behavior to observe.
- Loop until the check passes.
- "Looks right" is not a finish line. Verification is.
- If you can't define a check, you don't yet understand the task.

## 5. Keep files small and focused

- Prefer many small, focused files over a few sprawling ones.
- Never propose putting "everything in one file." It is hostile to maintenance.
- When a file grows hard for a human to navigate, suggest splitting it along natural seams: by responsibility, feature, screen, or layer.
- Follow the project's existing module boundaries. Don't invent a new structure mid-task.

## 6. Use the project's own tooling

- Before running a build, test, run, lint, or format command directly, check for a task runner: Taskfile, justfile, Makefile, npm/pnpm scripts, Rakefile, Maven/Gradle wrappers, etc.
- If one exists with a matching target, use it instead of invoking the underlying tool (mvn, gradle, go, npm, cargo, pytest, etc.) by hand.
- The task runner encodes flags, environment, and ordering that the raw command omits. Bypassing it produces results that don't match how the project actually builds and runs.
- Fall back to the raw tool only when no target covers what you need, and say why you are bypassing the runner.

## 7. Write code like a human will maintain it

- Optimize for the next reader. Code is read far more often than it is written.
- Boring and idiomatic beats clever. If a line needs decoding, rewrite it as the obvious version.
- Control flow should read top to bottom: early returns over deep nesting, related logic kept together.
- Comments explain why, not what. No narration of obvious code. Update or delete comments when the code they describe changes.
- Comments are terse. One line is the default, a second line has to earn its place, three or more should feel wrong. State the constraint; leave out the history, the alternatives, and the argument. Doc comments on exported identifiers use the language's summary-first form (godoc first sentence, JSDoc summary line).
- Shipped files stand alone. Never reference planning artifacts: no plan or spec numbering ("Plan 3", "spec section 4"), no decision labels ("D11"), no "the plan" / "the spec" / "the brief" / "per spec", and no process vocabulary ("this round", "the fix wave", "this session") meaning a unit of work. State the rule itself, not the document that decided it.
- No verification narration in comments ("verified by hand", "the test proves this", "was evaluated and returned 402"). That is reviewer talk and belongs in the task report.
- Future-work notes are phrased by component, not by task number: "once the auth service exists", never "Task 7 adds this".
- Apply DRY and SOLID with judgment, not as dogma. Extract shared code when duplication is real and repeated, not to pre-empt it. Theme 2 still wins: three similar lines beat a premature framework.
- The test: a maintainer with none of this conversation's context should understand the code from the code alone.

## 8. Triage review findings: fix now or decline with a reason

- A verified finding on code the task touched has two outcomes: fix it now, or decline it with a stated reason (the finding is wrong, or the behavior is intended). There is no later lane for polish. Deferred polish compounds into giant cleanup rounds.
- The backlog is for genuine scope changes a review surfaces: a new feature idea, a design question that needs its own discussion. Never for quality findings on the changed surface.
- "Covered indirectly" does not close a test gap. A sibling branch's green does not pin this branch. Write the direct test.
- Churn volume is not a reason to skip a fix. In work whose purpose is fixing existing problems, "too much churn" means leaving problems in.
- Documentation findings are fix-now too; they ride the same change.
- Verify before fixing. Every finding gets an adversarial check against the actual code before it drives an edit, so plausible-but-wrong findings do not ship as changes. The `finding-verifier` agent in this plugin does that check.
